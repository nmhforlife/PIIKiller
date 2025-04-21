import json
from presidio_analyzer import AnalyzerEngine
from presidio_custom_recognizer import CustomNameRecognizer

def test_custom_recognizer(names):
    """
    Test the custom name recognizer with a list of names
    
    Args:
        names (list): List of names to test
        
    Returns:
        dict: Results of the test
    """
    print("Initializing Presidio analyzer with custom name recognizer...")
    analyzer = AnalyzerEngine()
    custom_recognizer = CustomNameRecognizer()
    analyzer.registry.add_recognizer(custom_recognizer)
    
    total_names = len(names)
    detected_names = 0
    missed_names = []
    results = {}
    
    print("\nTesting names detection...\n")
    
    for name in names:
        print(f"Testing: '{name}'")
        analyzer_results = analyzer.analyze(
            text=name,
            language="en",
            entities=["PERSON"]
        )
        
        detected = False
        best_match = None
        best_score = 0
        
        for result in analyzer_results:
            # Only consider PERSON entities
            if result.entity_type == "PERSON":
                # Calculate coverage of the name
                coverage = (result.end - result.start) / len(name)
                
                # Check if this is a good match
                if result.score >= 0.6 and coverage >= 0.8:
                    detected = True
                
                # Track the best partial match
                if result.score > best_score:
                    best_score = result.score
                    best_match = result
        
        # Special case for email addresses
        if "@" in name and not detected:
            # If we found part of the name in the email, consider it detected
            for result in analyzer_results:
                if result.entity_type == "PERSON" and result.score >= 0.6:
                    detected = True
                    best_match = result
                    break
        
        if detected:
            detected_names += 1
            status = "DETECTED"
        else:
            missed_names.append(name)
            status = "MISSED"
            
        print(f"  Result: {status}")
        
        # Store detailed results
        results[name] = {
            "detected": detected,
            "best_match": None if best_match is None else {
                "text": name[best_match.start:best_match.end],
                "score": best_match.score,
                "start": best_match.start,
                "end": best_match.end,
                "recognition_source": best_match.recognition_metadata.get("recognizer_name", "unknown")
            },
            "all_results": [r.to_dict() for r in analyzer_results]
        }
    
    # Print summary results
    detection_rate = (detected_names / total_names) * 100
    print(f"\nSummary: Detected {detected_names} out of {total_names} names ({detection_rate:.1f}%)")
    
    if missed_names:
        print("\nMissed names:")
        for name in missed_names:
            print(f"  - '{name}'")
    
    # Save detailed results to a file
    with open("custom_recognizer_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    return {
        "total": total_names,
        "detected": detected_names,
        "missed": missed_names,
        "detection_rate": detection_rate,
        "detailed_results": results
    }

if __name__ == "__main__":
    # List of test names that were problematic before
    test_names = [
        # Names without spaces
        'JohnSmith',
        'JohnDoe',
        
        # Name with underscore
        'John_Doe',
        
        # ALL CAPS
        'JOHN SMITH',
        
        # Lowercase
        'john smith',
        
        # Names with commas
        'Smith,John',
        
        # Names with titles
        'Dr. John Smith',
        
        # Names with comma and space
        'Smith, John',
        
        # Middle initial
        'James T. Kirk',
        
        # Last name with prefix
        'McDowell',
        
        # Email address
        'john.smith@example.com',
        
        # Compound last name
        'van der Meer',
        
        # Name with apostrophe
        'O\'Connor',
        
        # Hyphenated last name
        'Sophie Smith-Johnson',
        
        # Short names
        'Li Wei',
        
        # Names with accents
        'José Rodríguez'
    ]
    
    test_custom_recognizer(test_names) 