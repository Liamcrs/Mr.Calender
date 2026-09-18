import SwiftUI
import UniformTypeIdentifiers

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false; @State private var showingAdd = false
    private var icsType: UTType { UTType(filenameExtension: "ics") ?? .data }
    var body: some View { NavigationStack { VStack { DatePicker("选择日期", selection: $store.selectedDate, displayedComponents: .date).datePickerStyle(.graphical).padding(.horizontal).onChange(of: store.selectedDate) { _, _ in store.refreshReminders() }; List {
        let labels = HolidayProvider.labels(on: store.selectedDate)
        if !labels.isEmpty { Section("节日与调休") { ForEach(labels, id: \.name) { Text($0.name).foregroundStyle($0.kind == .workday ? .orange : .green) } } }
        Section("安排") { ForEach(store.snapshot.events.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: store.selectedDate) }.sorted { $0.startsAt < $1.startsAt }) { event in VStack(alignment: .leading) { Text(event.title); Text(event.startsAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) } }.onDelete { index in store.snapshot.events.remove(atOffsets: index); store.refreshReminders() } }
    } }.navigationTitle("日历").toolbar { ToolbarItem(placement: .topBarLeading) { Button("导入课表") { showingImporter = true } }; ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } } }.fileImporter(isPresented: $showingImporter, allowedContentTypes: [icsType], allowsMultipleSelection: false) { result in
        switch result {
        case .success(let urls):
            guard let url = urls.first else { store.banner = "没有选择课表文件"; return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(decoding: Data(contentsOf: url), as: UTF8.self)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { store.banner = "课表文件为空"; return }
                store.importICS(text)
            } catch {
                store.banner = "无法读取课表文件：\(error.localizedDescription)"
            }
        case .failure(let error):
            store.banner = "选择课表失败：\(error.localizedDescription)"
        }
    }.sheet(isPresented: $showingAdd) { AddEventView() } } }
}

struct AddEventView: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var date = Date()
    var body: some View { NavigationStack { Form { TextField("标题", text: $title); DatePicker("时间", selection: $date) }.navigationTitle("添加安排").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { guard !title.isEmpty else { return }; store.addEvent(title: title, date: date); dismiss() } } } } }
}
