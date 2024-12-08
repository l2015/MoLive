import Foundation

enum ConversionError: Error {
    case invalidInput
    case conversionFailed
    case frameExtractionFailed
    case videoCreationFailed
    case xmpParsingError(String)
    case noPermission
} 