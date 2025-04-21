#!/bin/bash
# Enhanced setup script for Presidio environment with improved error handling
set -e  # Exit immediately if any command fails

echo "=== Setting up PIIKiller Python environment ==="

# Check for presence of custom files
HAS_CUSTOM_SERVER=false
HAS_CUSTOM_RECOGNIZER=false

if [ -f "presidio_server.py" ]; then
    if grep -q "monkey-patch\|CustomNameRecognizer" "presidio_server.py"; then
        echo "Found enhanced presidio_server.py - will preserve"
        HAS_CUSTOM_SERVER=true
        cp presidio_server.py presidio_server.py.bak
    fi
fi

if [ -f "presidio_custom_recognizer.py" ]; then
    echo "Found custom recognizer - will preserve"
    HAS_CUSTOM_RECOGNIZER=true
    cp presidio_custom_recognizer.py presidio_custom_recognizer.py.bak
fi

# Create and activate Python virtual environment
echo "Creating Python virtual environment..."
python3 -m venv presidio_env
source presidio_env/bin/activate

# Verify activation
if [ -z "$VIRTUAL_ENV" ]; then
    echo "Error: Failed to activate virtual environment."
    exit 1
fi

# Upgrade pip and install required packages
echo "Upgrading pip..."
pip install --upgrade pip setuptools wheel

echo "Installing required packages..."
pip install flask flask-cors

# Check Python version for compatibility mode
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
if [[ $PYTHON_VERSION == 3.1[23]* ]]; then
    echo "Using compatibility mode for Python 3.12/3.13"
    COMPATIBILITY_MODE=true
    SPACY_MODEL="en_core_web_sm"
    
    # Install binary packages for modern Python
    echo "Installing NumPy (required for spaCy)..."
    pip install --only-binary=numpy numpy
    
    # If that fails, try with a specific version
    if [ $? -ne 0 ]; then
        echo "Trying alternative NumPy installation..."
        pip install --only-binary=:all: numpy==1.26.0
    fi

    # Install spaCy and download the smaller model
    echo "Installing spaCy and downloading en_core_web_sm model..."
    pip install --only-binary=:all: spacy
    python -m spacy download en_core_web_sm
else
    echo "Using standard installation for Python < 3.12"
    COMPATIBILITY_MODE=false
    SPACY_MODEL="en_core_web_lg"
    
    # Install prerequisite packages
    echo "Installing prerequisites for spaCy..."
    pip install --only-binary=:all: numpy
    pip install --only-binary=:all: cython

    # Install spaCy
    echo "Installing spaCy and downloading en_core_web_lg model..."
    pip install --only-binary=:all: spacy
    python -m spacy download en_core_web_lg
fi

# Install Presidio packages
echo "Installing Presidio packages..."
pip install presidio-analyzer presidio-anonymizer

# If we don't have custom files, create default ones
if [ "$HAS_CUSTOM_SERVER" = false ]; then
    echo "Creating default presidio_server.py..."
    cat > presidio_server.py << 'EOF'
from flask import Flask, request, jsonify
from flask_cors import CORS
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import RecognizerResult, OperatorConfig
import logging
import re

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-server')

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Initialize analyzer and anonymizer
analyzer = AnalyzerEngine()
anonymizer = AnonymizerEngine()

@app.route('/health', methods=['GET', 'OPTIONS'])
def health():
    if request.method == 'OPTIONS':
        return '', 204
    
    return jsonify({"status": "healthy", "service": "presidio"}), 200

@app.route('/analyze', methods=['POST', 'OPTIONS'])
def analyze():
    if request.method == 'OPTIONS':
        return '', 204
        
    try:
        data = request.get_json()
        text = data.get('text', '')
        language = data.get('language', 'en')
        entities = data.get('entities', [])
        
        # Skip processing if text is very short
        if len(text) < 3:
            return jsonify([])

        # Get results from the analyzer
        results = analyzer.analyze(
            text=text,
            language=language,
            entities=entities
        )
        
        # Manually create dictionaries from RecognizerResult objects
        result_dicts = []
        for result in results:
            result_dict = {
                "entity_type": result.entity_type,
                "start": result.start,
                "end": result.end,
                "score": float(result.score)
            }
            
            if hasattr(result, "recognition_metadata"):
                result_dict["recognition_metadata"] = result.recognition_metadata
            
            result_dicts.append(result_dict)
        
        return jsonify(result_dicts)
    
    except Exception as e:
        logger.error(f"Error in analyze endpoint: {str(e)}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500

@app.route('/anonymize', methods=['POST', 'OPTIONS'])
def anonymize():
    if request.method == 'OPTIONS':
        return '', 204
        
    try:
        data = request.get_json()
        text = data.get('text', '')
        analyzer_results = data.get('analyzerResults', [])
        operators = data.get('operators', {})
        comment_info = data.get('commentInfo', {})
        
        # Skip processing if text is very short
        if len(text) < 3:
            return jsonify({"text": text, "metadata": comment_info})
        
        # If we have text but no analyzer results, run analyze first
        if text and not analyzer_results:
            standard_results = analyzer.analyze(
                text=text,
                language="en"
            )
                
            analyzer_results = []
            for result in standard_results:
                result_dict = {
                    "entity_type": result.entity_type,
                    "start": result.start,
                    "end": result.end,
                    "score": float(result.score)
                }
                
                if hasattr(result, "recognition_metadata"):
                    result_dict["recognition_metadata"] = result.recognition_metadata
                else:
                    result_dict["recognition_metadata"] = {"recognizer_name": "unknown"}
                    
                analyzer_results.append(result_dict)

        # Convert analyzer results to RecognizerResult objects
        results = []
        for result in analyzer_results:
            recognizer_result = RecognizerResult(
                entity_type=result['entity_type'],
                start=result['start'],
                end=result['end'],
                score=result['score']
            )
            
            if 'recognition_metadata' in result:
                recognizer_result.recognition_metadata = result['recognition_metadata']
            else:
                recognizer_result.recognition_metadata = {"recognizer_name": "unknown"}
                
            results.append(recognizer_result)

        # Convert operators to OperatorConfig objects
        operator_configs = {}
        for entity_type, config in operators.items():
            config_copy = config.copy()
            
            if 'type' in config_copy:
                del config_copy['type']
            if 'newValue' in config_copy:
                del config_copy['newValue']
                
            operator_name = 'replace'  # Default operator
            
            operator_configs[entity_type] = OperatorConfig(
                operator_name=operator_name,
                **config_copy
            )

        anonymized_result = anonymizer.anonymize(
            text=text,
            analyzer_results=results,
            operators=operator_configs
        )

        # Include comment metadata in the response
        response = {
            'text': anonymized_result.text,
            'metadata': comment_info
        }

        return jsonify(response)
        
    except Exception as e:
        logger.error(f"Error in anonymize endpoint: {str(e)}")
        
        # Return the original text with error metadata
        response = {
            'text': text,
            'error': str(e),
            'metadata': comment_info
        }
        return jsonify(response)

if __name__ == '__main__':
    logger.info("Starting Presidio server...")
    app.run(host='0.0.0.0', port=3001)
EOF
fi

if [ "$HAS_CUSTOM_RECOGNIZER" = false ]; then
    echo "Creating default custom_recognizer template..."
    cat > presidio_custom_recognizer.py << 'EOF'
from presidio_analyzer import EntityRecognizer, RecognizerResult
import re
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-custom')

class CustomNameRecognizer(EntityRecognizer):
    """
    Custom recognizer for person names.
    This is a template that you can expand with your own implementation.
    """
    
    def __init__(self):
        supported_entities = ["PERSON"]
        super().__init__(supported_entities=supported_entities, name="CustomNameRecognizer")
        
    def load(self):
        """No loading needed."""
        pass
        
    def analyze(self, text, entities, nlp_artifacts=None):
        """
        Analyzes text for person names.
        
        Args:
            text: The text to analyze
            entities: The entities to look for
            nlp_artifacts: NLP artifacts from the NLP engine
            
        Returns:
            A list of RecognizerResult
        """
        results = []
        
        # Check if we're interested in PERSON entities
        if "PERSON" not in entities:
            return results
            
        # Implement your custom logic here
        # For example, you could check for tabular data patterns, specific name formats, etc.
        
        return results

if __name__ == '__main__':
    # For testing purposes
    recognizer = CustomNameRecognizer()
    print("Custom recognizer initialized.")
EOF
fi

# Restore any backed up custom implementations
if [ "$HAS_CUSTOM_SERVER" = true ]; then
    echo "Restoring custom server implementation..."
    mv presidio_server.py.bak presidio_server.py
fi

if [ "$HAS_CUSTOM_RECOGNIZER" = true ]; then
    echo "Restoring custom recognizer implementation..."
    mv presidio_custom_recognizer.py.bak presidio_custom_recognizer.py
fi

# Update model in server if needed
if [ "$COMPATIBILITY_MODE" = true ]; then
    echo "Updating server to use smaller spaCy model..."
    sed -i.bak 's/en_core_web_lg/en_core_web_sm/g' presidio_server.py
fi

# Copy files to lib directory for packaging
mkdir -p presidio_env/lib
cp presidio_server.py presidio_env/lib/
if [ -f "presidio_custom_recognizer.py" ]; then
    cp presidio_custom_recognizer.py presidio_env/lib/
fi

echo "=== PIIKiller Python environment setup complete ==="
echo "You can now run: npm run dev"
echo "Or build the application: ./release.sh"

# Print version information for verification
echo ""
echo "=== Environment Information ==="
echo "Python version: $PYTHON_VERSION"
echo "spaCy model: $SPACY_MODEL"
echo "Server ready to start on port 3001"
echo "To start the server: source presidio_env/bin/activate && python presidio_server.py"