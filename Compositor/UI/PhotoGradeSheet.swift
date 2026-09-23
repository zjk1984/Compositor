import SwiftUI
import UniformTypeIdentifiers

/// Batch photo culling and development using Compositor's native photo-grade engine.
struct PhotoGradeSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var sourceFolder: URL?
    @State private var outputFolder: URL?
    @State private var preset: PhotoGradePreset = .general
    @State private var workflow: PhotoGradeWorkflow = .evaluate
    @State private var look: PhotoGradeLook = .natural
    @State private var keepS = true
    @State private var keepA = true
    @State private var keepB = false
    @State private var keepC = false
    @State private var previewDevelop = true
    @State private var straighten = false
    @State private var working = false
    @State private var status = ""
    @State private var error: String?
    @State private var results: [PhotoGradeEvaluation] = []
    @State private var developedOutputs: [URL] = []
    @State private var showsFolderPicker = false
    @State private var showsOutputPicker = false

    private var selectedTiers: [PhotoGradeTier] {
        var tiers: [PhotoGradeTier] = []
        if keepS { tiers.append(.s) }
        if keepA { tiers.append(.a) }
        if keepB { tiers.append(.b) }
        if keepC { tiers.append(.c) }
        return tiers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photo Grade Shoot").font(.title2.bold())
            Text("Evaluate RAW and JPEG files, tier them S/A/B/C, and optionally develop keepers using Core Image and Camera Raw.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Source") {
                HStack {
                    Text(sourceFolder?.path ?? "Choose a folder of photos…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(sourceFolder == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Folder…") { showsFolderPicker = true }
                }
            }

            GroupBox("Workflow") {
                Picker("Mode", selection: $workflow) {
                    ForEach(PhotoGradeWorkflow.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("Preset", selection: $preset) {
                    ForEach(PhotoGradePreset.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }

                if workflow == .pipeline {
                    Picker("Look", selection: $look) {
                        ForEach(PhotoGradeLook.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Toggle("Preview-sized develop (1600 px long edge)", isOn: $previewDevelop)
                    Toggle("Auto-straighten horizon", isOn: $straighten)
                    HStack {
                        Text(outputFolder?.path ?? "Output folder (defaults to source/edited)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose Output…") { showsOutputPicker = true }
                    }
                }

                if workflow != .evaluate {
                    Text("Keep tiers").font(.headline)
                    HStack {
                        Toggle("S", isOn: $keepS)
                        Toggle("A", isOn: $keepA)
                        Toggle("B", isOn: $keepB)
                        Toggle("C", isOn: $keepC)
                    }
                }
            }

            if working {
                ProgressView(status.isEmpty ? "Grading photos…" : status)
            } else if !status.isEmpty {
                Text(status).foregroundStyle(.secondary)
            }

            if !results.isEmpty {
                resultsTable
            }

            HStack {
                if !developedOutputs.isEmpty {
                    Button("Import Developed (\(developedOutputs.count))") {
                        Task { await importDeveloped() }
                    }
                }
                Spacer()
                Button("Close") { dismissSheet() }
                    .keyboardShortcut(.cancelAction)
                Button(runTitle) { Task { await runWorkflow() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceFolder == nil || working
                              || (workflow != .evaluate && selectedTiers.isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 520)
        .fileImporter(isPresented: $showsFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let url) = result { sourceFolder = url }
        }
        .fileImporter(isPresented: $showsOutputPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let url) = result { outputFolder = url }
        }
        .alert("Photo grade failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var runTitle: String {
        switch workflow {
        case .evaluate: "Evaluate"
        case .evaluateOrganize: "Evaluate & Organize"
        case .pipeline: "Run Pipeline"
        }
    }

    private var resultsTable: some View {
        Table(sortedResults) {
            TableColumn("Tier") { row in
                Text(row.tier).fontWeight(.semibold)
                    .foregroundStyle(tierColor(row.tierValue))
            }.width(40)
            TableColumn("Score") { Text(String(format: "%.1f", row.overallScore)) }.width(50)
            TableColumn("Sharp") { Text(String(format: "%.0f", row.sharpness)) }.width(45)
            TableColumn("DR") { Text(String(format: "%.0f", row.dynamicRange)) }.width(40)
            TableColumn("Flags") { Text(row.flags.isEmpty ? "ok" : row.flags.joined(separator: ", ")) }
            TableColumn("File") { Text(row.filename).lineLimit(1) }
        }
        .frame(minHeight: 180, maxHeight: 260)
    }

    private var sortedResults: [PhotoGradeEvaluation] {
        results.sorted {
            if $0.tierValue.sortRank != $1.tierValue.sortRank { return $0.tierValue.sortRank < $1.tierValue.sortRank }
            return $0.overallScore > $1.overallScore
        }
    }

    private func tierColor(_ tier: PhotoGradeTier) -> Color {
        switch tier {
        case .s: .purple
        case .a: .green
        case .b: .cyan
        case .c: .red
        }
    }

    private func runWorkflow() async {
        guard let folder = sourceFolder else { return }
        working = true
        error = nil
        status = "Running…"
        developedOutputs = []
        defer { working = false }

        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        do {
            switch workflow {
            case .evaluate:
                let batch = try await PhotoGradeService.evaluate(folder: folder, preset: preset, tiers: [])
                results = batch.results
                status = "Evaluated \(batch.totalCount) photos."
            case .evaluateOrganize:
                let organizeRoot = outputFolder ?? folder.appendingPathComponent("graded", isDirectory: true)
                let batch = try await PhotoGradeService.organize(folder: folder, preset: preset, destination: organizeRoot)
                results = batch.results
                status = "Organized \(batch.totalCount) photos into \(organizeRoot.path)/S,A,B,C."
            case .pipeline:
                let tiers = selectedTiers.isEmpty ? [.s, .a] : selectedTiers
                let out = outputFolder ?? folder.appendingPathComponent("edited", isDirectory: true)
                let manifest = try await PhotoGradeService.pipeline(folder: folder, preset: preset, tiers: tiers,
                                                                    look: look, output: out, preview: previewDevelop,
                                                                    straighten: straighten)
                developedOutputs = manifest.developed.map(\.outputURL)
                results = manifest.developed.map {
                    PhotoGradeEvaluation(path: $0.source, filename: URL(fileURLWithPath: $0.source).lastPathComponent,
                                         overallScore: $0.overallScore, tier: $0.tier,
                                         sharpness: 0, dynamicRange: 0, noiseControl: 0, colorHarmony: 0,
                                         composition: 0, flags: [], details: [:])
                }
                status = "Developed \(manifest.totalDeveloped) of \(manifest.totalEvaluated) photos into \(out.path)."
            }
        } catch {
            self.error = error.localizedDescription
            status = ""
        }
    }

    private func importDeveloped() async {
        dismissSheet()
        await session.importImages(developedOutputs)
    }

    private func dismissSheet() {
        session.showsPhotoGrade = false
    }
}

extension View {
    func photoGradeSheet(_ session: EditorSession) -> some View {
        sheet(isPresented: Binding(
            get: { session.showsPhotoGrade },
            set: { session.showsPhotoGrade = $0 }
        )) {
            PhotoGradeSheet(session: session)
        }
    }
}
