from flask import Flask, request, jsonify
from flask_cors import CORS
from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern
from presidio_analyzer.entity_recognizer import EntityRecognizer
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import RecognizerResult, OperatorConfig
import logging
import re
import spacy
from presidio_custom_recognizer import CustomNameRecognizer  # Import our enhanced recognizer

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-server')

# Monkey-patch the EntityRecognizer.remove_duplicates method to fix the contained_in error
def safe_remove_duplicates(results):
    """
    A safe implementation of remove_duplicates that doesn't use the contained_in method.
    This fixes the AttributeError: 'RecognizerResult' object has no attribute 'contained_in'
    """
    if not results:
        return []
        
    # Sort by start index and then by end index (longer matches first)
    sorted_results = sorted(results, key=lambda x: (x.start, -x.end))
    
    filtered_results = []
    for result in sorted_results:
        # Check if this result overlaps with any existing results
        is_duplicate = False
        for existing in filtered_results:
            # Check if this result is contained within an existing one
            if (result.start >= existing.start and result.end <= existing.end and 
                result.entity_type == existing.entity_type):
                is_duplicate = True
                break
            # Check if this result contains an existing one
            elif (existing.start >= result.start and existing.end <= result.end and 
                 result.entity_type == existing.entity_type):
                # The new result is larger and contains an existing one
                # Replace the existing one if the score is higher
                if result.score > existing.score:
                    filtered_results.remove(existing)
                    filtered_results.append(result)
                is_duplicate = True
                break
        
        # Add if not a duplicate
        if not is_duplicate:
            filtered_results.append(result)
            
    return filtered_results

# Apply the monkey patch
EntityRecognizer.remove_duplicates = safe_remove_duplicates

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Initialize analyzer with the enhanced custom recognizer
analyzer = AnalyzerEngine()
custom_recognizer = CustomNameRecognizer()
analyzer.registry.add_recognizer(custom_recognizer)
logger.info("Added enhanced name recognizer with tabular data support")

# Initialize anonymizer
anonymizer = AnonymizerEngine()

# Log that we're using standard Presidio recognizers with our enhanced recognizer
logger.info("Using standard Presidio recognizers with enhanced name detection for tabular data")

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
        
        # Skip processing if text is very short or appears to be random characters
        if len(text) < 3 or re.match(r'^[a-z]{1,5}$', text):
            return jsonify([])

        # Get results from the analyzer - our monkey patched remove_duplicates will be called
        results = analyzer.analyze(
            text=text,
            language=language,
            entities=entities
        )
        
        # Manually create dictionaries from RecognizerResult objects
        # since to_dict() doesn't exist in this version of Presidio
        result_dicts = []
        for result in results:
            # Create a dictionary representation of the RecognizerResult
            result_dict = {
                "entity_type": result.entity_type,
                "start": result.start,
                "end": result.end,
                "score": float(result.score)
            }
            
            # Add recognition_metadata if it exists
            if hasattr(result, "recognition_metadata"):
                result_dict["recognition_metadata"] = result.recognition_metadata
            
            result_dicts.append(result_dict)
        
        return jsonify(result_dicts)
    
    except Exception as e:
        # Log the full error traceback
        import traceback
        logger.error(f"Error in analyze endpoint: {str(e)}")
        logger.error(traceback.format_exc())
        # Return a 500 error with details
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
        comment_info = data.get('commentInfo', {})  # Get comment metadata
        
        # Skip processing if text is very short or appears to be random characters
        if len(text) < 3 or re.match(r'^[a-z]{1,5}$', text):
            return jsonify({"text": text, "metadata": {
                "author": comment_info.get('author', 'Unknown'),
                "authorType": comment_info.get('authorType', 'Unknown'),
                "timestamp": comment_info.get('timestamp', ''),
                "commentId": comment_info.get('commentId', '')
            }})
        
        # If we have the text but no analyzer results, run analyze first
        if text and not analyzer_results:
            # Get results from the analyzer (includes both standard and our enhanced recognizers)
            standard_results = analyzer.analyze(
                text=text,
                language="en"
            )
                
            # Manually create dictionaries from RecognizerResult objects
            analyzer_results = []
            for result in standard_results:
                # Create a dictionary representation of the RecognizerResult
                result_dict = {
                    "entity_type": result.entity_type,
                    "start": result.start,
                    "end": result.end,
                    "score": float(result.score)
                }
                
                # Add recognition_metadata if it exists
                if hasattr(result, "recognition_metadata"):
                    result_dict["recognition_metadata"] = result.recognition_metadata
                else:
                    result_dict["recognition_metadata"] = {"recognizer_name": "unknown"}
                    
                analyzer_results.append(result_dict)

        # Convert analyzer results to RecognizerResult objects
        results = []
        for result in analyzer_results:
            # Create a RecognizerResult with recognition_metadata properly handled
            recognizer_result = RecognizerResult(
                entity_type=result['entity_type'],
                start=result['start'],
                end=result['end'],
                score=result['score']
            )
            
            # Add recognition_metadata if available in the result
            if 'recognition_metadata' in result:
                recognizer_result.recognition_metadata = result['recognition_metadata']
            else:
                # Default metadata to prevent errors
                recognizer_result.recognition_metadata = {"recognizer_name": "unknown"}
                
            results.append(recognizer_result)

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
        
    except Exception as e:
        # Log the full error traceback
        import traceback
        logger.error(f"Error in anonymize endpoint: {str(e)}")
        logger.error(traceback.format_exc())
        
        # Return the original text with error metadata
        response = {
            'text': text,
            'error': str(e),
            'metadata': comment_info
        }
        return jsonify(response)

@app.route('/debug-analyze', methods=['POST'])
def debug_analyze():
    """Additional route for debugging name detection issues"""
    data = request.get_json()
    text = data.get('text', '')
    
    # Skip processing if text is very short or appears to be random characters
    if len(text) < 3 or re.match(r'^[a-z]{1,5}$', text):
        return jsonify({"text": text, "spacy_entities": [], "presidio_results": [], "enhanced_results": []})
    
    # Get raw spaCy results
    import spacy
    nlp = spacy.load("en_core_web_lg")
    doc = nlp(text)
    
    spacy_entities = [{"text": ent.text, "label": ent.label_, "start": ent.start_char, "end": ent.end_char} 
                      for ent in doc.ents]
    
    # Get enhanced Presidio results
    presidio_results = analyzer.analyze(
        text=text,
        language="en",
        return_decision_process=True
    )
    
    # Check if the text looks like tabular data
    is_tabular = custom_recognizer._is_tabular_data(text)
    
    # Collect token information for debugging
    tokens = [{"text": token.text, "pos": token.pos_, "tag": token.tag_, 
               "is_proper_noun": token.pos_ == "PROPN"} 
             for token in doc]
    
    # Build the debug info
    debug_info = {
        "text": text,
        "is_tabular_data": is_tabular,
        "spacy_entities": spacy_entities,
        "presidio_results": [
            {
                "entity_type": r.entity_type,
                "start": r.start,
                "end": r.end,
                "score": float(r.score),
                "recognizer": getattr(r, "recognition_metadata", {}).get("recognizer_name", "unknown"),
                "text": text[r.start:r.end]
            }
            for r in presidio_results
        ],
        "tokens": tokens,
        "recognizers": [rec.name for rec in analyzer.registry.recognizers]
    }
    
    return jsonify(debug_info)

if __name__ == '__main__':
    logger.info("Starting Presidio server with enhanced name detection for tabular data...")
    app.run(host='0.0.0.0', port=3001)
