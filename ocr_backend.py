import os
import sys
import json
import re
import argparse

# Global PaddleOCR instance (lazy initialized)
ocr_instance = None

def get_ocr():
    global ocr_instance
    if ocr_instance is None:
        from paddleocr import PaddleOCR
        # Initialize PaddleOCR
        # lang='en' is english, use_textline_orientation=True detects text orientation
        ocr_instance = PaddleOCR(use_textline_orientation=True, lang='en', enable_mkldnn=False)
    return ocr_instance

def run_ocr(image_path):
    ocr = get_ocr()
    result = ocr.ocr(image_path)
    
    # PaddleOCR returns a list of lists: [[[box, (text, confidence)], ...]]
    lines = []
    if result and len(result) > 0 and result[0] is not None:
        for idx in range(len(result)):
            res = result[idx]
            for line in res:
                text = line[1][0]
                lines.append(text.strip())
                
    return lines

def parse_medical_bill(lines):
    # Join lines for full text searches
    raw_text = "\n".join(lines)
    
    patient_name = None
    treatments = []
    medicines = []
    clinical_notes = []
    
    # 1. Extract Patient Name
    name_patterns = [
        r'(?:patient|name|patient\s+name|pt\.?\s+name)\s*[:\-]\s*([A-Za-z\s\.]{3,30})',
        r'mr\.?|ms\.?|mrs\.?\s+([A-Za-z\s\.]{3,30})'
    ]
    
    for pattern in name_patterns:
        match = re.search(pattern, raw_text, re.IGNORECASE)
        if match:
            patient_name = match.group(1).strip()
            patient_name = re.split(r'\n|\t|Date|Age|Sex|Gender', patient_name, flags=re.IGNORECASE)[0].strip()
            break
            
    # If not found, check lines sequentially
    if not patient_name:
        for line in lines:
            if re.search(r'patient|pt\.?\s*name', line, re.IGNORECASE):
                parts = re.split(r'[:\-]', line)
                if len(parts) > 1 and len(parts[1].strip()) > 2:
                    patient_name = parts[1].strip()
                    break
    
    # 2. Extract Treatments/Services and Medicines with prices
    # Price pattern: matches numbers with decimal (e.g. 150.00, 200.0) or integers >= 10 (e.g., 250, 1000)
    price_pattern = re.compile(r'(?:₹|rs\.?|\$)?\s*(\b\d+(?:\.\d{1,2})?\b)', re.IGNORECASE)
    
    # Common medicine indicator keywords
    med_keywords = [
        'tab', 'tablet', 'cap', 'capsule', 'syp', 'syrup', 'inj', 'injection',
        'mg', 'ml', 'g', 'mcg', 'suspension', 'cream', 'ointment', 'drops', 'gel'
    ]
    
    # Common clinical notes keywords
    notes_keywords = [
        'diagnosis', 'history', 'symptoms', 'complaints', 'observations', 'advice', 'investigation'
    ]
    
    for line in lines:
        cleaned_line = line.strip()
        if not cleaned_line:
            continue
            
        matches = price_pattern.findall(cleaned_line)
        if matches:
            price_str = matches[-1]
            try:
                price = float(price_str)
                # Filter out numbers that look like dates, years, or serial numbers
                if price > 20000 or price < 1 or (price >= 2020 and price <= 2030):
                    continue
                    
                # Extract the item name by removing the price and any currency symbols
                item_name = price_pattern.sub('', cleaned_line).strip()
                item_name = re.sub(r'^[•\-\*]\s*', '', item_name) # remove list bullets
                item_name = re.sub(r'[:\-₹\$]\s*$', '', item_name).strip() # remove trailing symbols
                
                if len(item_name) < 3:
                    continue
                
                # Check if it looks like a medicine
                is_med = any(f"\\b{kw}\\b" in item_name.lower() or item_name.lower().startswith(kw) for kw in med_keywords)
                dosage_match = re.search(r'\b([0-1]\s*-\s*[0-1]\s*-\s*[0-1])\b', cleaned_line)
                dosage = dosage_match.group(1).replace(" ", "") if dosage_match else ""
                
                if is_med:
                    med_name = re.sub(r'\b[0-1]\s*-\s*[0-1]\s*-\s*[0-1]\b', '', item_name).strip()
                    medicines.append({
                        "name": med_name,
                        "dosage": dosage if dosage else "1-0-1",
                        "price": price
                    })
                else:
                    treatments.append({
                        "name": item_name,
                        "price": price
                    })
            except ValueError:
                continue
                
        # Extract clinical notes
        for kw in notes_keywords:
            if re.search(rf'\b{kw}\b', cleaned_line, re.IGNORECASE):
                parts = re.split(rf'\b{kw}\b\s*[:\-]', cleaned_line, flags=re.IGNORECASE)
                if len(parts) > 1 and len(parts[1].strip()) > 3:
                    clinical_notes.append(parts[1].strip())
                else:
                    clinical_notes.append(cleaned_line)

    notes_str = "; ".join(clinical_notes) if clinical_notes else ""
    
    # If no treatments/medicines found with prices, fallback to raw text
    if not treatments and not medicines:
        notes_str = "Could not parse specific items. Raw text extracted:\n" + raw_text[:300]
        
    return {
        "patientName": patient_name,
        "treatments": treatments,
        "medicines": medicines,
        "clinicalNotes": notes_str,
        "rawText": raw_text
    }

def start_server(port):
    from flask import Flask, request, jsonify
    app = Flask(__name__)
    
    @app.route("/ocr", methods=["POST"])
    def ocr_endpoint():
        if "image" not in request.files:
            return jsonify({"error": "No image file provided"}), 400
            
        file = request.files["image"]
        if file.filename == "":
            return jsonify({"error": "No selected file"}), 400
            
        temp_path = "temp_ocr_upload.jpg"
        file.save(temp_path)
        
        try:
            lines = run_ocr(temp_path)
            result = parse_medical_bill(lines)
            return jsonify(result)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)
                
    print(f"Starting OCR Server on port {port}...")
    app.run(host="0.0.0.0", port=port, debug=False)

def parse_arguments():
    parser = argparse.ArgumentParser(description="PaddleOCR Medical Bill Parser")
    parser.add_argument("image_path", nargs="?", default=None, help="Path to image file for CLI mode")
    parser.add_argument("--server", action="store_true", help="Run as Flask server")
    parser.add_argument("--port", type=int, default=5000, help="Port for server")
    return parser.parse_args()

def main():
    args = parse_arguments()
    
    if args.server:
        start_server(args.port)
    elif args.image_path:
        if not os.path.exists(args.image_path):
            print(json.dumps({"error": f"Image file not found: {args.image_path}"}))
            sys.exit(1)
            
        try:
            lines = run_ocr(args.image_path)
            result = parse_medical_bill(lines)
            print(json.dumps(result))
        except Exception as e:
            print(json.dumps({"error": str(e)}))
            sys.exit(1)
    else:
        print("Please provide an image path or use --server")
        sys.exit(1)

if __name__ == "__main__":
    main()
