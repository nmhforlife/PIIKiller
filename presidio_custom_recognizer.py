from flask import Flask, request, jsonify
from flask_cors import CORS
from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern, EntityRecognizer
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import RecognizerResult, OperatorConfig
import re
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('presidio-custom')

# Create a custom pattern recognizer for names that might be missed by spaCy
class CustomNameRecognizer(EntityRecognizer):
    """
    Custom recognizer for person names with enhanced handling for tabular data.
    This recognizer identifies names in various formats that might be missed by the default recognizer.
    """
    
    def __init__(self):
        supported_entities = ["PERSON"]
        super().__init__(supported_entities=supported_entities, name="CustomNameRecognizer")
        
    def load(self):
        """No loading needed."""
        pass
        
    def analyze(self, text, entities, nlp_artifacts=None):
        """
        Analyzes text for person names with special focus on tabular data.
        
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
            
        # First, check if this looks like tabular data
        if self._is_tabular_data(text):
            # Use reduced logging - don't log actual data
            logger.info("Analyzing tabular data structure")
            tabular_results = self._analyze_tabular_data(text)
            results.extend(tabular_results)
            
        # Then apply general name pattern matching
        pattern_results = self._apply_name_patterns(text)
        results.extend(pattern_results)
        
        return results
    
    def _is_tabular_data(self, text):
        """
        Detects if the text appears to be in a tabular format.
        
        Args:
            text: The text to analyze
            
        Returns:
            bool: True if text appears to be in tabular format
        """
        lines = text.split('\n')
        if len(lines) < 2:
            return False
            
        # Look for consistent spacing/formatting that indicates columns
        column_indicators = 0
        
        # Check for header-like rows mentioning names, SSNs, credit cards, etc.
        header_terms = ['name', 'ssn', 'social security', 'credit card', 'first', 'last', 
                        'customer', 'email', 'phone', 'address', 'visa', 'mc', 'amex']
        
        header_line_found = False
        for i in range(min(3, len(lines))):
            line = lines[i].lower()
            # Check for header terms
            if any(term in line for term in header_terms):
                header_line_found = True
                column_indicators += 1
                
            # Check for consistent multi-space or tab formatting
            if len(re.findall(r'\s{2,}|\t', line)) > 1:
                column_indicators += 1
                
        # Look for consistent SSN or credit card number patterns
        ssn_pattern = re.compile(r'\d{3}-\d{2}-\d{4}')
        cc_pattern = re.compile(r'\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}')
        
        pattern_count = 0
        for i in range(min(len(lines), 6)):  # Check first few lines
            line = lines[i]
            if ssn_pattern.search(line) or cc_pattern.search(line):
                pattern_count += 1
                
        # If we found multiple indicators, it's likely tabular
        return column_indicators >= 2 or pattern_count >= 2 or header_line_found
    
    def _analyze_tabular_data(self, text):
        """
        Extract names from tabular data using structural analysis.
        
        Args:
            text: The text to analyze
            
        Returns:
            list: RecognizerResult objects for detected names
        """
        results = []
        lines = text.split('\n')
        
        # Try to identify the column structure
        column_structure = self._identify_columns(lines)
        name_column = column_structure.get('name_column')
        separator_type = column_structure.get('separator_type')
        column_positions = column_structure.get('column_positions', [])
        
        # Process each line to extract names from the identified name column
        for i, line in enumerate(lines):
            # Skip likely header rows and empty lines
            if i < column_structure.get('data_start_line', 1) or not line.strip():
                continue
                
            # Extract potential name based on the identified structure
            potential_name = None
            
            if name_column is not None:
                if separator_type == 'spaces':
                    # For space-separated columns
                    potential_name = self._extract_column_by_position(line, name_column, column_positions)
                elif separator_type in ['tab', 'comma']:
                    # For delimiter-separated columns
                    delimiter = '\t' if separator_type == 'tab' else ','
                    columns = line.split(delimiter)
                    if 0 <= name_column < len(columns):
                        potential_name = columns[name_column].strip()
            else:
                # If we couldn't identify a specific name column, try first column or first part
                # before SSN/credit card number
                ssn_match = re.search(r'\d{3}-\d{2}-\d{4}', line)
                cc_match = re.search(r'\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}', line)
                
                if ssn_match or cc_match:
                    match_pos = ssn_match.start() if ssn_match else cc_match.start()
                    potential_name = line[:match_pos].strip()
                    
                    # If potential name is too long, try to extract just the last 1-3 words
                    # which are more likely to be the actual name
                    if len(potential_name.split()) > 3:
                        name_parts = potential_name.split()
                        if len(name_parts) >= 2:
                            potential_name = ' '.join(name_parts[-2:])
                        else:
                            potential_name = name_parts[-1]
            
            # Validate and add the name if it looks legitimate
            if potential_name and self._looks_like_name(potential_name):
                # Find the actual position in the full text
                name_pos = text.find(potential_name)
                if name_pos >= 0:
                    # Removed name logging for privacy
                    result = RecognizerResult(
                        entity_type="PERSON",
                        start=name_pos,
                        end=name_pos + len(potential_name),
                        score=0.85
                    )
                    # Add metadata using attribute assignment instead of constructor
                    result.recognition_metadata = {
                        "recognizer_name": self.name,
                        "pattern_name": "tabular_data"
                    }
                    results.append(result)
        
        return results
    
    def _identify_columns(self, lines):
        """
        Identify column structure in tabular data.
        
        Args:
            lines: List of text lines
            
        Returns:
            dict: Information about column structure
        """
        structure = {
            'name_column': None,
            'separator_type': None,
            'column_positions': [],
            'data_start_line': 1
        }
        
        if not lines:
            return structure
            
        # Analyze the first few lines to determine the separator and find headers
        for i in range(min(3, len(lines))):
            line = lines[i]
            if not line.strip():
                continue
                
            # Check for different separator types
            tabs = line.count('\t')
            commas = line.count(',')
            spaces = len(re.findall(r'\s{2,}', line))
            
            # Determine likely separator
            if tabs > 1:
                structure['separator_type'] = 'tab'
            elif commas > 1:
                structure['separator_type'] = 'comma'
            elif spaces > 1:
                structure['separator_type'] = 'spaces'
                # Find positions of multiple spaces
                structure['column_positions'] = [m.start() for m in re.finditer(r'\s{2,}', line)]
                
            # Look for headers suggesting name columns
            lower_line = line.lower()
            if 'first' in lower_line and 'last' in lower_line and 'name' in lower_line:
                structure['name_column'] = 0
                structure['data_start_line'] = i + 1
            elif 'name' in lower_line:
                # Try to determine which column contains the name
                if structure['separator_type'] == 'spaces':
                    # For space-separated columns, find which section contains "name"
                    last_pos = 0
                    for j, pos in enumerate(structure['column_positions']):
                        column_text = lower_line[last_pos:pos]
                        if 'name' in column_text:
                            structure['name_column'] = j
                            structure['data_start_line'] = i + 1
                            break
                        last_pos = pos
                    # Check the last column
                    if 'name' in lower_line[last_pos:]:
                        structure['name_column'] = len(structure['column_positions'])
                        structure['data_start_line'] = i + 1
                elif structure['separator_type'] in ['tab', 'comma']:
                    delimiter = '\t' if structure['separator_type'] == 'tab' else ','
                    columns = lower_line.split(delimiter)
                    for j, col in enumerate(columns):
                        if 'name' in col:
                            structure['name_column'] = j
                            structure['data_start_line'] = i + 1
                            break
        
        # If we couldn't identify a name column but detected tabular structure,
        # assume the first column contains names (common convention)
        if structure['separator_type'] and structure['name_column'] is None:
            structure['name_column'] = 0
            
        return structure
    
    def _extract_column_by_position(self, line, column_index, column_positions):
        """
        Extract a column from a line based on positions of column separators.
        
        Args:
            line: The text line
            column_index: Index of the column to extract
            column_positions: List of positions where columns are separated
            
        Returns:
            str: The extracted column text
        """
        if not column_positions:
            return line.strip()
            
        if column_index == 0:
            # First column
            return line[:column_positions[0]].strip()
        elif column_index < len(column_positions):
            # Middle column
            start_pos = column_positions[column_index-1]
            end_pos = column_positions[column_index]
            return line[start_pos:end_pos].strip()
        else:
            # Last column
            return line[column_positions[-1]:].strip()
    
    def _apply_name_patterns(self, text):
        """
        Apply regex patterns to detect names.
        
        Args:
            text: The text to analyze
            
        Returns:
            list: RecognizerResult objects for detected names
        """
        results = []
        
        # Define patterns for different name formats
        patterns = [
            # Standard first and last name (First Last)
            (r'\b[A-Z][a-zA-Z\'\-]+\s+[A-Z][a-zA-Z\'\-]+\b', 0.75, "standard_name"),
            
            # Name with middle initial (First M. Last)
            (r'\b[A-Z][a-zA-Z\'\-]+\s+[A-Z]\.?\s+[A-Z][a-zA-Z\'\-]+\b', 0.85, "middle_initial"),
            
            # Name with title (Mr./Mrs./Ms./Dr. First Last)
            (r'\b(Mr\.|Mrs\.|Ms\.|Dr\.|Prof\.)\s+[A-Z][a-zA-Z\'\-]+(\s+[A-Z][a-zA-Z\'\-]+)+\b', 0.85, "titled_name"),
            
            # Last name, First name format
            (r'\b[A-Z][a-zA-Z\'\-]+,\s*[A-Z][a-zA-Z\'\-]+\b', 0.8, "last_first_format"),
            
            # Names in ALL CAPS
            (r'\b[A-Z]{2,}(\s+[A-Z]{2,})+\b', 0.7, "all_caps_name"),
            
            # Names with apostrophes like O'Connor
            (r"\b[A-Z][a-zA-Z\-]+\'[A-Z]?[a-zA-Z\-]+\b", 0.8, "apostrophe_name"),
            
            # Names with hyphens like Smith-Jones
            (r"\b[A-Z][a-zA-Z]+\-[A-Z][a-zA-Z]+\b", 0.8, "hyphenated_name"),
            
            # First letter capitalized with spaces, more relaxed
            (r"\b[A-Z][a-z]+(\s+[A-Z][a-z]+){1,2}\b", 0.6, "relaxed_name")
        ]
        
        for pattern, score, pattern_name in patterns:
            matches = re.finditer(pattern, text)
            for match in matches:
                match_text = match.group()
                
                # Skip matches that don't look like real names
                if not self._looks_like_name(match_text):
                    continue
                    
                # Check if we already found this name
                already_found = False
                for result in results:
                    if result.start <= match.start() and result.end >= match.end():
                        already_found = True
                        break
                        
                if not already_found:
                    logger.info(f"Found name with pattern matching: '{match_text}'")
                    result = RecognizerResult(
                        entity_type="PERSON",
                        start=match.start(),
                        end=match.end(),
                        score=score
                    )
                    # Add metadata using attribute assignment instead of constructor
                    # This avoids the TypeError we were getting
                    result.recognition_metadata = {
                        "recognizer_name": self.name,
                        "pattern_name": pattern_name
                    }
                    results.append(result)
        
        return results
    
    def _looks_like_name(self, text):
        """
        Check if text looks like a legitimate personal name.
        
        Args:
            text: Text to check
            
        Returns:
            bool: True if text looks like a name
        """
        # Clean up the text
        text = text.strip()
        
        # Skip if too short or too long
        if len(text) < 4 or len(text) > 40:
            return False
            
        # Skip common non-name words
        common_words = [
            "test", "example", "demo", "sample", "user", "customer", "client",
            "hello", "world", "system", "program", "data", "file", "server",
            "please", "thank", "thanks", "help", "support", "service",
            "update", "status", "report", "document", "project",
            "appears", "volume", "volumes", "amount", "total", "number",
            "first", "last", "name", "address", "email", "phone",
            "monday", "tuesday", "wednesday", "thursday", "friday",
            "january", "february", "march", "april", "may", "june", "july",
            "august", "september", "october", "november", "december",
            "credit", "card", "number", "visa", "mc", "amex", "mastercard"
        ]
        
        lower_text = text.lower()
        for word in common_words:
            if lower_text == word:
                return False
                
        # Skip if it's a single word without capitals
        if ' ' not in text and not any(c.isupper() for c in text):
            return False
            
        # Skip if it has suspicious characters for a name
        if re.search(r'[0-9@#$%^&*()\[\]{}<>?/\\|=+]', text):
            return False
            
        # Skip common sentence fragments
        if text.lower().startswith(('the ', 'and ', 'but ', 'for ', 'with ', 'from ')):
            return False
            
        # Check if text has proper capitalization for a name
        words = text.split()
        capital_ratio = sum(1 for word in words if word and word[0].isupper()) / len(words)
        
        if capital_ratio < 0.5:  # At least half the words should start with capital letters
            return False
            
        return True

def create_enhanced_presidio_server(missed_names=None):
    """
    Create a Flask server with an enhanced Presidio analyzer that includes custom name recognition.
    
    Args:
        missed_names: Optional list of specific names to add to the recognizer
        
    Returns:
        Flask app with enhanced Presidio capabilities
    """
    app = Flask(__name__)
    CORS(app)  # Enable CORS for all routes
    
    # Initialize the analyzer with custom recognizers
    analyzer = AnalyzerEngine()
    
    # Add our custom name recognizer
    custom_name_recognizer = CustomNameRecognizer()
    analyzer.registry.add_recognizer(custom_name_recognizer)
    logger.info("Added enhanced name recognizer with tabular data support")
    
    # If we have specific names that are being missed, add them as patterns
    if missed_names and len(missed_names) > 0:
        patterns = []
        for name in missed_names:
            # Escape special regex characters in the name
            escaped_name = re.escape(name)
            pattern = Pattern(
                name=f"Specific name: {name}",
                regex=f"\\b{escaped_name}\\b",
                score=0.9  # High score for exact matches
            )
            patterns.append(pattern)
        
        specific_name_recognizer = PatternRecognizer(
            supported_entity="PERSON",
            patterns=patterns,
            supported_language="en"
        )
        analyzer.registry.add_recognizer(specific_name_recognizer)
        logger.info(f"Added specific name patterns for: {', '.join(missed_names)}")
    
    # Initialize the anonymizer
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
        results = []
        for result in analyzer_results:
            rec_result = RecognizerResult(
                entity_type=result['entity_type'],
                start=result['start'],
                end=result['end'],
                score=result['score']
            )
            # Add metadata as attribute instead of constructor parameter
            if 'recognition_metadata' in result:
                rec_result.recognition_metadata = result['recognition_metadata']
            else:
                rec_result.recognition_metadata = {"recognizer_name": "unknown"}
            results.append(rec_result)

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
        
        # Get Presidio results
        presidio_results = analyzer.analyze(
            text=text,
            language="en",
            return_decision_process=True
        )
        
        # Run custom analysis separately
        is_tabular = custom_name_recognizer._is_tabular_data(text)
        
        # Build the debug info without logging actual content
        debug_info = {
            "text_length": len(text),
            "is_tabular_data": is_tabular,
            "spacy_entity_count": len(spacy_entities),
            "presidio_result_count": len(presidio_results),
            "recognizers": [rec.name for rec in analyzer.registry.recognizers],
            "patterns_checked": True
        }
        
        return jsonify(debug_info)
    
    return app

if __name__ == '__main__':
    # Create the server without specific hardcoded names
    app = create_enhanced_presidio_server()
    
    # Run the server
    print("Starting enhanced Presidio server on port 3001...")
    app.run(host='0.0.0.0', port=3001) 