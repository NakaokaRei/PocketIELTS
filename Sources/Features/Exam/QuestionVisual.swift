import SwiftUI

/// Portable vector artwork: travels with saved papers and needs no remote image URL.
struct QuestionVisual: Codable, Equatable, Sendable {
    var title: String
    var description: String
    var elements: [Element]
    var imageData: Data? = nil
    var imageGenerationFailed: Bool? = nil

    struct Element: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case box, circle, line, arrow, label }
        var kind: Kind
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var label: String
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160 &&
        !description.isEmpty && description.count <= 3000 &&
        (1...60).contains(elements.count) && elements.allSatisfy { item in
            let values = [item.x, item.y, item.width, item.height]
            return values.allSatisfy(\.isFinite) &&
                (0...100).contains(item.x) && (0...100).contains(item.y) &&
                (0...100).contains(item.x + item.width) && (0...100).contains(item.y + item.height) &&
                (item.kind == .line || item.kind == .arrow || (item.width > 0 && item.height > 0)) && item.label.count <= 100
        }
    }

    static func validate(_ visuals: [Self]?, instructions: [String] = []) throws {
        let requiresFigure = instructions.contains {
            $0.range(of: #"(?i)\b(?:map|plan|diagram|chart|figure)\s+(?:below|above)|\blabel\s+(?:the\s+)?(?:map|plan|diagram)\b"#, options: .regularExpression) != nil
        }
        guard let visuals, !visuals.isEmpty else {
            if requiresFigure { throw StudyError.message(String(localized: "必要な教材が揃いませんでした。もう一度お試しください。")) }
            return
        }
        guard visuals.count <= 4, visuals.allSatisfy(\.isValid) else {
            throw StudyError.message(String(localized: "必要な教材が揃いませんでした。もう一度お試しください。"))
        }
    }

    static let generationInstructions = """
    You can create visual material using an optional top-level "visuals" array (empty when not needed).
    For maps, plans, diagram labelling, processes, or a task referring to a figure, you MUST include the figure.
    Use original, readable schematic vector artwork, not a photo URL, Markdown image, SVG, or external asset.
    For Listening Part 2 vary task types and include map/plan labelling when appropriate; do not always copy the example's question type.
    For General Training Reading, vary task types and include diagram/plan labelling or flow-chart completion when supported by the passage. Supply a complete figure with numbered blanks and unambiguous evidence in the text.
    All skills support visuals, but preserve General Training formats: Writing Task 1 is a letter, NOT an Academic chart report; Speaking need not contain a figure.
    Each visual has {"title":"Community centre plan","description":"Accessible description of the visible layout only","elements":[{"kind":"box","x":5,"y":5,"width":25,"height":20,"label":"A"}]}.
    Coordinate canvas is 100 by 100, displayed at a 4:3 aspect ratio. Limit to 4 visuals and 60 elements each.
    Kinds: box (room/bar/process), circle (landmark), label (text area), line or arrow (start x,y; end x+width,y+height).
    Coordinates/endpoints must stay in 0...100. Boxes/circles/labels need positive width and height.
    Every element needs all six fields; label can be empty. Labels <=100 characters; use short English labels, generous boxes and no overlapping labels.
    Include orientation, entrances, paths, keys, units and axis labels when relevant. Charts use boxes for bars and labelled axes.
    Use blank numbers or letters for locations being tested. NEVER write the answers in the figure, title, or accessible description.
    Ensure the audio/text, diagram positions, question numbers, answers and explanations agree. The description must convey the same visible information for accessibility without revealing the answer key.
    Do not ask a visual-dependent question without providing its visual. Return only completed artwork, not a promise or placeholder.
    """

    static func context(_ visuals: [Self]?) -> String {
        guard let visuals, !visuals.isEmpty else { return "" }
        let textOnly = visuals.map { visual in
            var copy = visual; copy.imageData = nil; copy.imageGenerationFailed = nil; return copy
        }
        guard let data = try? JSONEncoder().encode(textOnly) else { return "" }
        return "\nVISUAL MATERIAL (coordinates on a 100 × 100 canvas):\n" + String(decoding: data, as: UTF8.self)
    }
}

struct QuestionVisualView: View {
    let visual: QuestionVisual
    @State private var expanded = false
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(visual.title).font(StudyTypography.headline)
                Spacer()
                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(StudyColors.accent)
                    .accessibilityLabel(String(localized: "Expand figure"))
                    .accessibilityIdentifier("question.visual.expand")
            }
            artwork.aspectRatio(4 / 3, contentMode: .fit)
            if visual.imageData != nil {
                Toggle(String(localized: "Show original diagram"), isOn: $showOriginal)
                    .font(StudyTypography.subheadline)
            } else if visual.imageGenerationFailed == true {
                Text(String(localized: "Image generation failed; showing the original diagram."))
                    .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
            }
        }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    GeometryReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            artwork.frame(width: max(900, proxy.size.width), height: max(900, proxy.size.width) * 0.75).padding(20)
                        }
                    }.navigationTitle(visual.title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button(String(localized: "完了")) { expanded = false } }
                }
            }
    }

    @ViewBuilder private var artwork: some View {
        if !showOriginal, let data = visual.imageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
                .accessibilityLabel(visual.description).accessibilityIdentifier("question.visual")
        } else {
            vectorArtwork
        }
    }

    private var vectorArtwork: some View {
        Canvas { context, size in
            let sx = size.width / 100, sy = size.height / 100
            for element in visual.elements {
                let rect = CGRect(x: element.x * sx, y: element.y * sy, width: element.width * sx, height: element.height * sy)
                if element.kind == .box || element.kind == .circle {
                    let path = element.kind == .circle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 6)
                    context.fill(path, with: .color(StudyColors.accent.opacity(0.08)))
                    context.stroke(path, with: .color(StudyColors.accent), lineWidth: max(1, size.width / 400))
                }
                if element.kind == .line || element.kind == .arrow {
                    let start = CGPoint(x: rect.origin.x, y: rect.origin.y)
                    let end = CGPoint(x: (element.x + element.width) * sx, y: (element.y + element.height) * sy)
                    var path = Path(); path.move(to: start); path.addLine(to: end)
                    if element.kind == .arrow {
                        let angle = atan2(end.y - start.y, end.x - start.x)
                        let length = size.width / 60
                        for offset in [-0.5, 0.5] {
                            path.move(to: end)
                            path.addLine(to: CGPoint(x: end.x - cos(angle + offset) * length, y: end.y - sin(angle + offset) * length))
                        }
                    }
                    context.stroke(path, with: .color(StudyColors.accent), lineWidth: max(1, size.width / 400))
                } else if !element.label.isEmpty {
                    let bounds = rect.insetBy(dx: 3, dy: 3)
                    var fontSize = max(11, size.width / 38)
                    var text = context.resolve(Text(element.label).font(.system(size: fontSize, weight: .semibold, design: .rounded)).foregroundColor(StudyColors.ink))
                    var measured = text.measure(in: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
                    for _ in 0..<12 where measured.height > bounds.height {
                        fontSize *= 0.9
                        text = context.resolve(Text(element.label).font(.system(size: fontSize, weight: .semibold, design: .rounded)).foregroundColor(StudyColors.ink))
                        measured = text.measure(in: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
                    }
                    context.draw(text, in: CGRect(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2,
                                                  width: measured.width, height: measured.height))
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(visual.description)
            .accessibilityIdentifier("question.visual")
    }
}
