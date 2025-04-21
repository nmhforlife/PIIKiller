#!/bin/bash

# Ensure we use a compatible Python version
PYTHON_CMD=""

# Check for Python 3.9, 3.10, or 3.11 (most compatible with spaCy)
for version in "python3.9" "python3.10" "python3.11" "python3.8"; do
    if command -v $version &> /dev/null; then
        PYTHON_CMD=$version
        echo "Using $PYTHON_CMD (recommended for spaCy compatibility)"
        break
    fi
done

# Fall back to python3 if specific versions not found
if [ -z "$PYTHON_CMD" ]; then
    PYTHON_CMD="python3"
    # Check if it's Python 3.13 (which has compatibility issues with spaCy)
    PYTHON_VERSION=$($PYTHON_CMD --version | awk '{print $2}')
    if [[ $PYTHON_VERSION == 3.13* ]]; then
        echo "⚠️ Warning: Python $PYTHON_VERSION detected, which has known compatibility issues with spaCy."
        echo "⚠️ Consider using Python 3.9, 3.10, or 3.11 instead."
        echo "⚠️ Attempting to continue, but build errors may occur."
    fi
    echo "Using $PYTHON_CMD (version $PYTHON_VERSION)"
fi

# Create and activate virtual environment
echo "Creating virtual environment..."
$PYTHON_CMD -m venv presidio_env
source presidio_env/bin/activate

# Install required packages
echo "Installing Presidio packages..."
pip install presidio_analyzer
pip install presidio_anonymizer
pip install flask
pip install flask-cors

# Install spaCy and download model with verification
echo "Installing spaCy model (this may take a while)..."
python -m pip install spacy
python -m spacy download en_core_web_lg

# Verify spaCy model installation
echo "Verifying spaCy model installation..."
python -c "
import spacy
try:
    nlp = spacy.load('en_core_web_lg')
    print('✅ spaCy model en_core_web_lg loaded successfully!')
    print(f'Model location: {nlp.path}')
except Exception as e:
    print(f'❌ Error loading spaCy model: {e}')
    exit(1)
"

if [ $? -ne 0 ]; then
    echo "Error: spaCy model verification failed. Please check the error message above."
    echo "You can try downloading the model manually after setup with:"
    echo "  source presidio_env/bin/activate"
    echo "  python -m spacy download en_core_web_lg"
    # Continue anyway to set up other components
fi

# Check if the custom presidio_server.py already exists
if [ -f "presidio_server.py" ]; then
    # Check if this file has our customizations
    if grep -q "monkey-patch" "presidio_server.py" || grep -q "CustomNameRecognizer" "presidio_server.py"; then
        echo "Found existing custom presidio_server.py with enhancements - preserving this file"
        # Create a backup just in case
        cp presidio_server.py presidio_server.py.bak
    else
        echo "Found existing presidio_server.py without enhancements - creating default file"
        # Create the default Flask server 
        create_default_server=true
    fi
else
    echo "No existing presidio_server.py found - creating default file"
    create_default_server=true
fi

# Only create the default server file if needed
if [ "$create_default_server" = true ]; then
    # Create a simple Flask server to expose Presidio
    echo "Creating Flask server..."
    cat > presidio_server.py << 'EOL'
from flask import Flask, request, jsonify
from flask_cors import CORS
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import RecognizerResult, OperatorConfig
import os
import sys
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-server')

# Ensure spaCy model is available
try:
    import spacy
    import en_core_web_lg
    logger.info(f"Using spaCy model from: {en_core_web_lg.__file__}")
except ImportError:
    logger.warning("Model en_core_web_lg not found as module, will attempt to load it")

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes
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
        
    data = request.get_json()
    text = data.get('text', '')
    language = data.get('language', 'en')
    entities = data.get('entities', [])

    results = analyzer.analyze(
        text=text,
        language=language,
        entities=entities
    )
    
    return jsonify([result.to_dict() for result in results])

@app.route('/anonymize', methods=['POST', 'OPTIONS'])
def anonymize():
    if request.method == 'OPTIONS':
        return '', 204
        
    data = request.get_json()
    text = data.get('text', '')
    analyzer_results = data.get('analyzerResults', [])
    operators = data.get('operators', {})
    comment_info = data.get('commentInfo', {})  # Get comment metadata

    # Convert analyzer results to RecognizerResult objects
    results = [
        RecognizerResult(
            entity_type=result['entity_type'],
            start=result['start'],
            end=result['end'],
            score=result['score']
        )
        for result in analyzer_results
    ]

    # Convert operators to OperatorConfig objects
    operator_configs = {}
    for entity_type, config in operators.items():
        # Create a copy of the config without unsupported parameters
        config_copy = config.copy()
        
        # Remove unsupported parameters
        if 'type' in config_copy:
            del config_copy['type']
        if 'newValue' in config_copy:
            del config_copy['newValue']
            
        # Set the operator name based on the entity type
        operator_name = 'replace'  # Default operator
        if entity_type == 'EMAIL_ADDRESS':
            operator_name = 'replace'
        elif entity_type == 'PHONE_NUMBER':
            operator_name = 'replace'
        elif entity_type == 'SSN':
            operator_name = 'replace'
        elif entity_type == 'CREDIT_CARD':
            operator_name = 'replace'
        elif entity_type == 'IP_ADDRESS':
            operator_name = 'replace'
        elif entity_type == 'PERSON':
            operator_name = 'replace'
        elif entity_type == 'DATE_TIME':
            operator_name = 'replace'
        elif entity_type == 'ADDRESS':
            operator_name = 'replace'
            
        # Create the operator config with the required parameters
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
        'metadata': {
            'author': comment_info.get('author', 'Unknown'),
            'authorType': comment_info.get('authorType', 'Unknown'),  # 'agent' or 'end_user'
            'timestamp': comment_info.get('timestamp', ''),
            'commentId': comment_info.get('commentId', '')
        }
    }

    return jsonify(response)

if __name__ == '__main__':
    logger.info("Starting Presidio server on port 3001...")
    app.run(host='0.0.0.0', port=3001)
EOL
fi

# Also check for our custom recognizer file
if [ ! -f "presidio_custom_recognizer.py" ]; then
    echo "Creating custom name recognizer for enhanced detection..."
    # Create a basic template for the custom recognizer
    cat > presidio_custom_recognizer.py << 'EOL'
from presidio_analyzer import PatternRecognizer, Pattern, EntityRecognizer
from presidio_anonymizer.entities import RecognizerResult
import re
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-custom')

class CustomNameRecognizer(EntityRecognizer):
    """
    Custom recognizer for person names with enhanced handling for tabular data.
    This recognizer identifies names in various formats that might be missed
    by the default recognizer.
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
        
        # Define basic name patterns
        patterns = [
            # Standard first and last name (First Last)
            (r'\b[A-Z][a-zA-Z\'\-]+\s+[A-Z][a-zA-Z\'\-]+\b', 0.75),
            
            # Name with middle initial (First M. Last)
            (r'\b[A-Z][a-zA-Z\'\-]+\s+[A-Z]\.?\s+[A-Z][a-zA-Z\'\-]+\b', 0.85),
            
            # Name with title (Mr./Mrs./Ms./Dr. First Last)
            (r'\b(Mr\.|Mrs\.|Ms\.|Dr\.|Prof\.)\s+[A-Z][a-zA-Z\'\-]+(\s+[A-Z][a-zA-Z\'\-]+)+\b', 0.85),
        ]
        
        for pattern, score in patterns:
            matches = re.finditer(pattern, text)
            for match in matches:
                result = RecognizerResult(
                    entity_type="PERSON",
                    start=match.start(),
                    end=match.end(),
                    score=score
                )
                # Add metadata using attribute assignment instead of constructor
                result.recognition_metadata = {
                    "recognizer_name": self.name,
                    "pattern_name": pattern
                }
                results.append(result)
        
        return results

# This function can be used to create a server with the custom recognizer
def create_enhanced_presidio_server():
    from flask import Flask, request, jsonify
    from flask_cors import CORS
    from presidio_analyzer import AnalyzerEngine
    from presidio_anonymizer import AnonymizerEngine
    
    app = Flask(__name__)
    CORS(app)
    
    # Initialize the analyzer with custom recognizers
    analyzer = AnalyzerEngine()
    analyzer.registry.add_recognizer(CustomNameRecognizer())
    
    # Initialize the anonymizer
    anonymizer = AnonymizerEngine()
    
    return app, analyzer, anonymizer
EOL
fi

echo "Checking for presidio_server.py..."
if [ -f "presidio_server.py" ]; then
    echo "✅ Presidio server script exists!"
else
    echo "⚠️ Warning: presidio_server.py not found!"
fi

echo "Checking for presidio_custom_recognizer.py..."
if [ -f "presidio_custom_recognizer.py" ]; then
    echo "✅ Custom recognizer script exists!"
else
    echo "⚠️ Warning: presidio_custom_recognizer.py not found!"
fi

# Create a simple script to reload the spaCy model if needed
echo "Creating a model verification script..."
cat > verify_spacy_model.py << 'EOL'
import spacy
import sys
import os

def verify_model():
    """Verify that the spaCy model is properly installed and working."""
    print("Verifying spaCy model installation...")
    try:
        # Try to load the model
        nlp = spacy.load('en_core_web_lg')
        print(f"✅ Model loaded successfully from: {nlp.path}")
        
        # Test a simple sentence to make sure it works
        text = "John Smith lives in New York and works at Microsoft."
        doc = nlp(text)
        entities = [(ent.text, ent.label_) for ent in doc.ents]
        print(f"Entities detected: {entities}")
        return True
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

if __name__ == "__main__":
    success = verify_model()
    if not success:
        print("\nTo fix this issue, try running:")
        print("  source presidio_env/bin/activate")
        print("  python -m spacy download en_core_web_lg")
        sys.exit(1)
EOL

# Run the verification script
echo "Running model verification..."
python verify_spacy_model.py

echo "Setup complete! You can now run the application with 'npm run dev'" 