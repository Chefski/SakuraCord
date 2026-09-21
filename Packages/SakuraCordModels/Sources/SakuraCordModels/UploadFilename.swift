import Foundation

public enum UploadFilename {
    public static func anonymised(_ filename: String) -> String {
        let fileExtension = (filename as NSString).pathExtension
        let basename = UUID().uuidString.lowercased()
        let name = fileExtension.isEmpty ? basename : "\(basename).\(fileExtension)"
        return filename.hasPrefix("SPOILER_") ? "SPOILER_\(name)" : name
    }
}
