#!/bin/bash
# Enhanced setup script for Presidio environment with improved error handling
set -e  # Exit immediately if any command fails

echo "=== Setting up PIIKiller Python environment ==="

# Create a fresh virtual environment
echo "Creating Python virtual environment..."
python3 -m venv presidio_env

# Use absolute paths to ensure we're using the right Python/pip
VENV_PYTHON="$(pwd)/presidio_env/bin/python"
VENV_PIP="$(pwd)/presidio_env/bin/pip"

echo "Using Python at: $VENV_PYTHON"
echo "Using pip at: $VENV_PIP"

# Upgrade pip to latest version
echo "Upgrading pip..."
$VENV_PYTHON -m pip install --upgrade pip

# Install wheel first to help with binary packages
echo "Installing wheel..."
$VENV_PIP install wheel

# Install required packages with explicit versions for stability
echo "Installing required packages..."
$VENV_PIP install flask==2.3.3
$VENV_PIP install flask-cors==4.0.0
$VENV_PIP install presidio-analyzer==2.2.33
$VENV_PIP install presidio-anonymizer==2.2.33

# Install spaCy with explicit version
echo "Installing spaCy..."
$VENV_PIP install spacy==3.6.1

# Download the spaCy model
echo "Downloading spaCy model..."
$VENV_PYTHON -m spacy download en_core_web_lg

# Verify installation
echo "Verifying installation..."
if ! $VENV_PYTHON -c "import spacy, presidio_analyzer, presidio_anonymizer, flask" 2>/dev/null; then
    echo "ERROR: Package verification failed. Something went wrong with the installation."
    exit 1
fi

echo "Package verification successful."

# Check if the custom presidio_server.py already exists
if [ -f "presidio_server.py" ]; then
    # Check if this file has our customizations
    if grep -q "monkey-patch" "presidio_server.py" || grep -q "CustomNameRecognizer" "presidio_server.py"; then
        echo "Found existing custom presidio_server.py with enhancements - preserving this file"
        # Create a backup just in case
        cp presidio_server.py presidio_server.py.bak
        
        # Copy to lib directory for packaging
        mkdir -p presidio_env/lib
        cp presidio_server.py presidio_env/lib/
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
    app.run(host='0.0.0.0', port=3001)
EOL

    # Also copy to lib directory for packaging
    mkdir -p presidio_env/lib
    cp presidio_server.py presidio_env/lib/
fi

# Also check for our custom recognizer file
if [ -f "presidio_custom_recognizer.py" ]; then
    echo "Found custom name recognizer - copying for packaging"
    # Copy to lib directory
    mkdir -p presidio_env/lib
    cp presidio_custom_recognizer.py presidio_env/lib/
else
    echo "Creating custom name recognizer for enhanced detection..."
    # Create a basic template for the custom recognizer
    cat > presidio_custom_recognizer.py << 'EOL'
from presidio_analyzer import PatternRecognizer, Pattern, EntityRecognizer
from presidio_anonymizer.entities import RecognizerResult
import re

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

    # Copy to lib directory for packaging
    mkdir -p presidio_env/lib
    cp presidio_custom_recognizer.py presidio_env/lib/
fi

echo "=== PIIKiller Python environment setup complete ==="
echo "You can now run: npm run dev"
echo "Or build the application: ./release.sh"

# Print version information for verification
echo ""
echo "=== Environment Information ==="
echo "Python version: $($VENV_PYTHON --version)"
echo "spaCy version: $($VENV_PYTHON -c 'import spacy; print(spacy.__version__)')"
echo "Presidio Analyzer version: $($VENV_PYTHON -c 'import presidio_analyzer; print(presidio_analyzer.__version__)')"
echo "Presidio Anonymizer version: $($VENV_PYTHON -c 'import presidio_anonymizer; print(presidio_anonymizer.__version__)')"
echo "Flask version: $($VENV_PYTHON -c 'import flask; print(flask.__version__)')" 

chmod +x setup_presidio.sh release.sh fix_env.sh