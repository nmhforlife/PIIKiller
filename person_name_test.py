import sys
import json
from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern
from presidio_analyzer.nlp_engine import NlpArtifacts
import spacy

def test_name_detection(names, debug=True):
    """
    Test how well Presidio detects a list of person names.
    
    Args:
        names: List of person names to test
        debug: Whether to print detailed debug information
    
    Returns:
        Dictionary with detection statistics
    """
    # Initialize Presidio analyzer
    analyzer = AnalyzerEngine()
    
    # Also get the spaCy model directly to see what it detects
    nlp = spacy.load("en_core_web_lg")
    
    results = {
        "total": len(names),
        "detected": 0,
        "missed": 0,
        "detected_names": [],
        "missed_names": [],
        "detailed_analysis": []
    }
    
    for name in names:
        if debug:
            print(f"\n{'='*50}\nTesting name: '{name}'")
            
        # First check what raw spaCy detects
        doc = nlp(name)
        spacy_entities = [(ent.text, ent.label_) for ent in doc.ents]
        
        # Then use Presidio analyzer
        analyzer_results = analyzer.analyze(
            text=name,
            language="en",
            entities=["PERSON"],
            return_decision_process=True
        )
        
        # Check if the name was detected
        detected = False
        detailed_info = {
            "name": name,
            "detected": False,
            "spacy_entities": spacy_entities,
            "presidio_results": []
        }
        
        for result in analyzer_results:
            # Convert the result to a serializable dict, but handle analysis_explanation specially
            result_dict = result.to_dict()
            # Remove the analysis_explanation which isn't JSON serializable
            if 'analysis_explanation' in result_dict:
                explanation = result_dict['analysis_explanation']
                if hasattr(explanation, 'recognizer'):
                    result_dict['explanation'] = {
                        'recognizer': explanation.recognizer,
                        'original_score': explanation.original_score,
                        'textual_explanation': explanation.textual_explanation
                    }
                del result_dict['analysis_explanation']
                
            detailed_info["presidio_results"].append(result_dict)
            
            if result.entity_type == "PERSON" and result.start == 0 and result.end == len(name):
                detected = True
                detailed_info["detected"] = True
                detailed_info["score"] = result.score
        
        # Add other spaCy insights
        tokens = [(token.text, token.pos_, token.tag_) for token in doc]
        detailed_info["tokens"] = tokens
        
        # Check the NER tags to see why it might have failed
        if not detected and debug:
            print(f"MISSED: '{name}'")
            print(f"  spaCy entities: {spacy_entities}")
            print(f"  Tokens: {tokens}")
            
            # Print a simplified version of the results to avoid serialization issues
            simple_results = []
            for r in analyzer_results:
                simple_results.append({
                    'entity_type': r.entity_type,
                    'start': r.start,
                    'end': r.end,
                    'score': r.score
                })
            print(f"  Presidio results: {simple_results}")
            
            # If no entities were recognized, explain why
            if not spacy_entities:
                print("  No entities recognized by spaCy at all.")
                word_vectors = [(token.text, token.has_vector, token.vector_norm) for token in doc]
                print(f"  Word vectors: {word_vectors}")
                
                for token in doc:
                    # Check if the token might be similar to known person names
                    if token.pos_ == "PROPN":
                        most_similar = find_most_similar_to_names(token)
                        print(f"  '{token.text}' most similar to names: {most_similar}")
        
        results["detailed_analysis"].append(detailed_info)
        
        if detected:
            results["detected"] += 1
            results["detected_names"].append(name)
        else:
            results["missed"] += 1
            results["missed_names"].append(name)
    
    # Calculate statistics
    results["detection_rate"] = results["detected"] / results["total"] if results["total"] > 0 else 0
    
    # Summary
    if debug:
        print("\n" + "="*50)
        print(f"SUMMARY: Detected {results['detected']}/{results['total']} names ({results['detection_rate']*100:.1f}%)")
        print(f"Missed names: {results['missed_names']}")
    
    return results

def find_most_similar_to_names(token, top_n=5):
    """Find most similar tokens to known names from spaCy's vocabulary."""
    # A small sample of common names to test similarity against
    common_names = ["John", "Mary", "Robert", "Sarah", "Michael", "David", "Jennifer", "James", "Thomas", "Patricia"]
    
    similarities = []
    for name in common_names:
        if name in token.vocab:
            similarities.append((name, token.similarity(token.vocab[name])))
    
    # Sort by similarity score
    similarities.sort(key=lambda x: x[1], reverse=True)
    return similarities[:top_n]

def create_person_recognizer(names_list):
    """Create a custom pattern recognizer for specific names."""
    patterns = []
    for name in names_list:
        # Escape special regex characters in the name
        escaped_name = ''.join('\\' + c if c in '.^$*+?()[]{}|\\' else c for c in name)
        pattern = Pattern(
            name=f"Person name: {name}",
            regex=f"\\b{escaped_name}\\b",
            score=0.85
        )
        patterns.append(pattern)
    
    return PatternRecognizer(
        supported_entity="PERSON",
        patterns=patterns,
        context=["person", "name", "called", "known as"]
    )

if __name__ == "__main__":
    # Sample names to test - add your problematic names here
    test_names = [
        "John Smith",
        "Jane Doe",
        "Robert Johnson",
        "Sarah Williams",
        "Michael Brown",
        "David Miller",
        "Jennifer Garcia",
        "James Wilson",
        "Thomas Moore",
        "Patricia Taylor"
    ]
    
    # If names are provided as command-line arguments, use those instead
    if len(sys.argv) > 1:
        test_names = sys.argv[1:]
    
    # Run the test
    results = test_name_detection(test_names, debug=True)
    
    # Write the detailed results to a JSON file
    with open('name_detection_results.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nDetailed results saved to 'name_detection_results.json'")
    
    # For any missed names, you could create a custom recognizer:
    if results["missed_names"]:
        print("\nTo improve detection, you could add a custom recognizer with these patterns:")
        custom_recognizer = create_person_recognizer(results["missed_names"])
        print("Add to your code:")
        print("custom_recognizer = create_person_recognizer(", results["missed_names"], ")")
        print("analyzer = AnalyzerEngine()")
        print("analyzer.registry.add_recognizer(custom_recognizer)") 