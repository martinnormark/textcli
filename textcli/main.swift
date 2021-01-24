//
//  main.swift
//  textcli
//
//  Created by Martin Høst Normark on 15/01/2021.
//

import Foundation
import Vision
import CoreImage
import AppKit

let args = CommandLine.arguments
var image: NSImage? = nil

print(args)

guard args.count >= 2 else {
    print("You must specify a path to the files you want to recognize text in.")
    
    exit(EXIT_FAILURE)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputPath = inputURL
    .deletingPathExtension()
    .appendingPathExtension("json").path

let recognitionLevel: VNRequestTextRecognitionLevel = args.count >= 3 && args[2] == "--fast" ? .fast : .accurate

print(outputPath)

struct BoundingBox: Encodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct TextCandidate: Encodable {
    var text: String
    var confidence: Double
    var bbox: BoundingBox
}

func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
    let context = CIContext(options: nil)
    if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
        return cgImage
    }
    return nil
}

func recognizeTextHandler(request: VNRequest, error: Error?) {
    guard let observations =
            request.results as? [VNRecognizedTextObservation] else {
        return
    }
    
    guard let image = image else { return }
    
    let imageWidth = image.representations.first!.pixelsWide
    let imageHeight = image.representations.first!.pixelsHigh
    
    let boundingRects: [TextCandidate] = observations.compactMap { observation in

        // Find the top observation.
        if let candidate = observation.topCandidates(1).first {
            // Find the bounding-box observation for the string range.
            let stringRange = candidate.string.startIndex..<candidate.string.endIndex
            let boxObservation = try? candidate.boundingBox(for: stringRange)
            
            // Get the normalized CGRect value.
            let boundingBox = boxObservation?.boundingBox ?? .zero
            
            // Convert the rectangle from normalized coordinates to image coordinates.
            let bboxArray = VNImageRectForNormalizedRect(boundingBox, imageWidth, imageHeight)
            let bbox = BoundingBox(
                x: Double(bboxArray.origin.x),
                y: Double(CGFloat(imageHeight) - bboxArray.origin.y - bboxArray.size.height),
                    width: Double(bboxArray.size.width),
                   height: Double(bboxArray.size.height))
            
            return TextCandidate(text: candidate.string, confidence: Double(candidate.confidence), bbox: bbox)
        }
        
        return nil
    }
    
    // Process the recognized strings.
    processResults(boundingRects)
}

func processResults(_ results: [TextCandidate]) {
    
    let jsonEncoder = JSONEncoder()
    let jsonData = try! jsonEncoder.encode(results)
    let json = String(data: jsonData, encoding: String.Encoding.utf8)
    
    do {
        try json!.write(toFile: outputPath, atomically: true, encoding: String.Encoding.utf8)
    }
    catch let error as NSError {
        print("Ooops! Something went wrong: \(error)")
    }
}

// Get the CGImage on which to perform requests.
if let nsImage = NSImage(contentsOf: inputURL), let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    image = nsImage

    // Create a new image-request handler.
    let requestHandler = VNImageRequestHandler(cgImage: cgImage)

    // Create a new request to recognize text.
    let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
    request.recognitionLevel = recognitionLevel

    do {
        // Perform the text-recognition request.
        try requestHandler.perform([request])
    } catch {
        print("Unable to perform the requests: \(error).")
        
        exit(EXIT_FAILURE)
    }
    
    exit(EXIT_SUCCESS)
}
else {
    print("file not loaded")
    exit(EXIT_FAILURE)
}
