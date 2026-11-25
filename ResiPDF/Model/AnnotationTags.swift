import PDFKit

/// Etiquetas clínicas (Dx, Tx, Cx…) guardadas DENTRO del PDF, en el nombre
/// estándar de la anotación (/NM): «resi:<grupo>#<línea>|Dx,Cx».
/// Así viajan con el archivo y se sincronizan con él.
enum AnnotationTags {
    static func tags(of a: PDFAnnotation) -> [String] {
        guard let name = a.value(forAnnotationKey: .name) as? String,
              let bar = name.firstIndex(of: "|") else { return [] }
        return name[name.index(after: bar)...]
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    static func baseName(of a: PDFAnnotation) -> String? {
        guard let name = a.value(forAnnotationKey: .name) as? String else { return nil }
        return name.components(separatedBy: "|").first
    }

    static func setTags(_ tags: [String], on a: PDFAnnotation) {
        guard let base = baseName(of: a) else { return }
        let value = tags.isEmpty ? base : base + "|" + tags.joined(separator: ",")
        a.setValue(value, forAnnotationKey: .name)
    }
}
