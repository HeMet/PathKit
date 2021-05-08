// PathKit - Effortless path operations

#if os(Windows)
import Foundation
import WinSDK

// Path conversion
extension String {
    /// Converts Windows path to Unix-like path.
    ///
    /// Steps:
    /// - if path is relative path with disk designator
    /// then path resolved
    /// - all path separators replaced with `/`
    /// - disk designator prepended with `/` if any
    func windowsPathAsUnixPath() -> String {
        if isEmpty { return self }

        var path = self
        if path.isRelativePathWithDiskDesignator {
            path = getFullPath(path: path) ?? path
        }

        var result = path.replacingOccurrences(of: "\\", with: Path.separator)

        if result.hasDriverDesignatorPrefix {
            result = Path.separator + result
        }

        if result != Path.separator && result.hasSuffix(Path.separator) {
            result.removeLast()
        }

        return result
    }

    /// Converts Unix-like to Windows path
    ///
    /// Method removes leading `/` if it prepends disk designator.
    func unixPathAsWindowsPath() -> String {
        var result = self
        let maybeAbsolutePathWithDiskDesignator = String(dropFirst())
        if maybeAbsolutePathWithDiskDesignator.hasDriverDesignatorPrefix {
            result = maybeAbsolutePathWithDiskDesignator
        }
        return result
    }

    var isDiskDesignator: Bool {
        return count == 2 && hasDriverDesignatorPrefix
    }

    private var isRelativePathWithDiskDesignator: Bool {
        if count < 3 {
            return false
        }

        let third = self[index(startIndex, offsetBy: 2)]
        return hasDriverDesignatorPrefix
            && third != "\\" && third != "/"
    }

    private var hasDriverDesignatorPrefix: Bool {
        if count < 2 {
            return false
        }

        let first = self[startIndex]
        let second = self[index(after: startIndex)]
        return first.isASCII && first.isLetter
            && second == ":"
    }
}

extension Collection where Element == String {
    func unixPathComponentsAsWindowsPathComponents() -> [String] {
        var result = Array(self)
        if result.count >= 2 && result[0] == Path.separator && result[1].isDiskDesignator {
            result.removeFirst()
        }
        return result
    }

    func windowsPathComponentsAsUnixPathComponents() -> [String] {
        var result = Array(self)
        if first?.isDiskDesignator == true {
            result.insert(Path.separator, at: 0)
        }
        return result
    }
}

extension RandomAccessCollection where Element == String {
    var isWindowsPathRoot: Bool {
        let isDiskDesignator = last?.isDiskDesignator == true
        let isRoot = count == 1 && last == Path.separator
        return isDiskDesignator || isRoot
    }
}

// String WCHAR support
private extension Array where Array.Element == WCHAR {
    init(from string: String) {
        self = string.withCString(encodedAs: UTF16.self) { buffer in
            Array<WCHAR>(unsafeUninitializedCapacity: string.utf16.count + 1) {
                wcscpy_s($0.baseAddress, $0.count, buffer)
                $1 = $0.count
            }
        }
    }
}

private extension String {
    var wide: [WCHAR] {
        return Array<WCHAR>(from: self)
    }
}

// Globbing
func windowsGlob(pattern: String) -> [String] {
    var components = Path(pattern).absolute().components
    let firstPattern = components.removeFirst()
    var result: [String] = []
    recursiveGlob(path: firstPattern, remainingPatterns: components, results: &result)
    return result
}

private func recursiveGlob(path: String, remainingPatterns: [String], results: inout [String]) {
    if remainingPatterns.isEmpty {
        results.append(path)
        return
    }

    var nextRemainingPatterns  = remainingPatterns
    let pathWithPattern: String = path + Path.separator + nextRemainingPatterns.removeFirst()
    findFiles(pattern: pathWithPattern) { matchedName, isDirectory in
        if matchedName == "." || matchedName == ".." {
            return
        }

        let matchedPath: String = path + Path.separator + matchedName
        recursiveGlob(path: matchedPath, remainingPatterns: nextRemainingPatterns, results: &results)
    }
}

private func findFiles(pattern: String, body: (String, Bool) -> Void) {
    var findData = _WIN32_FIND_DATAW()
    let hFind = FindFirstFileW(pattern.wide, &findData)
    if hFind == INVALID_HANDLE_VALUE {
        return
    }

    let firstFindString = withUnsafePointer(to: &findData.cFileName.0) { ptr -> String in
        return String(decodingCString: ptr, as: UTF16.self)
    }

    let isDirectory = findData.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == DWORD(FILE_ATTRIBUTE_DIRECTORY)
    body(firstFindString, isDirectory)

    while FindNextFileW(hFind, &findData) {
        let find = withUnsafePointer(to: &findData.cFileName.0) { ptr -> String in
            return String(decodingCString: ptr, as: UTF16.self)
        }
        let isDirectory = findData.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == DWORD(FILE_ATTRIBUTE_DIRECTORY)
        body(find, isDirectory)
    }

    FindClose(hFind)
}

// MARK: Getting absolute path

private func getFullPath(path: String) -> String? {
    var buffer = UnsafeMutableBufferPointer<WCHAR>.allocate(capacity: 4096)

    var resultLength = GetFullPathNameW(path.wide, 4096, buffer.baseAddress, nil)
    if resultLength > 4096 {
        buffer.deallocate()

        buffer = UnsafeMutableBufferPointer<WCHAR>.allocate(capacity: Int(resultLength))
        resultLength = GetFullPathNameW(path.wide, resultLength, buffer.baseAddress, nil)
    }

    if resultLength == 0 {
        buffer.deallocate()
        return nil
    }

    let result = String(decodingCString: buffer.baseAddress!, as: UTF16.self)
    buffer.deallocate()
    return result
}

#endif