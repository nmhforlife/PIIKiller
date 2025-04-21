#!/bin/bash

# Create and activate virtual environment
echo "Creating virtual environment..."
python3 -m venv presidio_env
source presidio_env/bin/activate

# Install required packages
echo "Installing Presidio packages..."
pip install presidio_analyzer
pip install presidio_anonymizer
pip install flask
pip install flask-cors
python -m spacy download en_core_web_lg

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
fi

# Also check for our custom recognizer file
if [ ! -f "presidio_custom_recognizer.py" ]; then
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
fi

echo "Checking for presidio_server.py..."
if [ -f "presidio_server.py" ]; then
    echo "Presidio server script exists!"
else
    echo "Warning: presidio_server.py not found!"
fi

echo "Checking for presidio_custom_recognizer.py..."
if [ -f "presidio_custom_recognizer.py" ]; then
    echo "Custom recognizer script exists!"
else
    echo "Warning: presidio_custom_recognizer.py not found!"
fi

# Run the server
echo "Starting Presidio server on port 3001..."
python presidio_server.py 