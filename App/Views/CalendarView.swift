import SwiftUI
import UniformTypeIdentifiers

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImportName = false
    @State private var showingImporter = false
    @State private var pendingTimetableName = ""
    @State private var showingAdd = false

    private var icsType: UTType { UTType(filenameExtension: "ics") ?? .data }

    private var selectedDayEvents: [CalendarEvent] {
        store.snapshot.activeEvents
            .filter { Calendar.current.isDate($0.startsAt, inSameDayAs: store.selectedDate) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("选择日期", selection: $store.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                List {
                    let labels = HolidayProvider.labels(on: store.selectedDate)
                    if !labels.isEmpty {
                        Section("节日与调休") {
                            ForEach(labels, id: \.name) { label in
                                Text(label.name)
                                    .foregroundStyle(label.kind == .workday ? .orange : .green)
                            }
                        }
                    }
                    Section("安排") {
                        ForEach(selectedDayEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                Text(event.startsAt, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !event.location.isEmpty {
                                    Label(event.location, systemImage: "mappin.and.ellipse")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !event.presentationNotes.isEmpty {
                                    Text(event.presentationNotes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { selectedDayEvents[$0].id }
                            for id in ids { store.deleteEvent(id: id) }
                        }
                    }
                }
            }
            .navigationTitle("日历")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("导入课表") { showingImportName = true }
                    NavigationLink("管理课表") { TimetableManagementView() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("新课表", isPresented: $showingImportName) {
                TextField("课表名称", text: $pendingTimetableName)
                Button("取消", role: .cancel) { pendingTimetableName = "" }
                Button("选择文件") {
                    let name = pendingTimetableName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        store.banner = "课表名称不能为空"
                        return
                    }
                    pendingTimetableName = name
                    showingImporter = true
                }
            } message: {
                Text("例如：大二上、辅修课表")
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [icsType], allowsMultipleSelection: false) { result in
                defer { pendingTimetableName = "" }
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { store.banner = "没有选择课表文件"; return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let text = try String(decoding: Data(contentsOf: url), as: UTF8.self)
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { store.banner = "课表文件为空"; return }
                        store.importICS(text, timetableName: pendingTimetableName)
                    } catch {
                        store.banner = "无法读取课表文件：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    store.banner = "选择课表失败：\(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showingAdd) { AddEventView() }
        }
    }
}

struct TimetableManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false
    @State private var reimportingTimetableID: UUID?
    @State private var timetablePendingDeletion: Timetable?
    @State private var showingDeleteConfirmation = false

    private var icsType: UTType { UTType(filenameExtension: "ics") ?? .data }

    var body: some View {
        List {
            ForEach(store.snapshot.timetables) { timetable in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        timetable.name,
                        isOn: Binding(
                            get: { store.snapshot.timetables.first(where: { $0.id == timetable.id })?.isEnabled ?? false },
                            set: { store.setTimetableEnabled(id: timetable.id, isEnabled: $0) }
                        )
                    )
                    Text("\(store.snapshot.events(for: timetable.id).count) 节课程 · 导入于 \(timetable.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重新导入") {
                        reimportingTimetableID = timetable.id
                        showingImporter = true
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        timetablePendingDeletion = timetable
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("管理课表")
        .confirmationDialog("删除课表及其所有课程？", isPresented: $showingDeleteConfirmation, presenting: timetablePendingDeletion) { timetable in
            Button("删除\(timetable.name)", role: .destructive) {
                store.deleteTimetable(id: timetable.id)
                timetablePendingDeletion = nil
            }
        } message: { timetable in
            Text("这将删除“\(timetable.name)”中的所有课程。")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [icsType], allowsMultipleSelection: false) { result in
            defer { reimportingTimetableID = nil }
            guard let timetableID = reimportingTimetableID else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { store.banner = "没有选择课表文件"; return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(decoding: Data(contentsOf: url), as: UTF8.self)
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { store.banner = "课表文件为空"; return }
                    store.importICS(text, replacing: timetableID)
                } catch {
                    store.banner = "无法读取课表文件：\(error.localizedDescription)"
                }
            case .failure(let error):
                store.banner = "选择课表失败：\(error.localizedDescription)"
            }
        }
    }
}

struct AddEventView: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var date = Date(); @State private var notes = ""
    var body: some View { NavigationStack { Form { TextField("标题", text: $title); DatePicker("时间", selection: $date); Section("备注（可选）") { TextEditor(text: $notes).frame(minHeight: 100) } }.dismissKeyboardOnTap().navigationTitle("添加安排").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { guard !title.isEmpty else { return }; store.addEvent(title: title, date: date, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } } } } }
}
