import SwiftUI
import PhotosUI
import UIKit

struct FoodView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
    @State private var picked: Dish?
    @State private var previewPhoto: DishPhotoPreview?
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let picked {
                    SectionCard(title: "今天吃这个？") {
                        if let photoURL = store.photoURL(for: picked.photoPath) {
                            Button { previewPhoto = DishPhotoPreview(url: photoURL) } label: {
                                DishPhotoThumbnail(url: photoURL, height: 180)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(picked.name).font(.title2.bold())
                        if let restaurant = store.snapshot.restaurants.first(where: { $0.id == picked.restaurantID }) {
                            Text(restaurant.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("就吃这个！") { confirmPicked(picked) }
                                .buttonStyle(.borderedProminent)
                            Button("再转一次") { reroll(picked) }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Button(action: spin) {
                        VStack(spacing: 12) {
                            Image(systemName: "die.face.5").font(.system(size: 54))
                            Text("帮我转一个").font(.title2.bold())
                            Text("会自动避开过敏原和今天已出现的菜").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(24)
                        .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                }
                List {
                    let categories = Dictionary(grouping: store.snapshot.restaurants, by: \.category).keys.sorted()
                    ForEach(categories, id: \.self) { category in
                        Section(category) {
                            ForEach(store.snapshot.restaurants.filter { $0.category == category }) { restaurant in
                                DisclosureGroup(restaurant.name) {
                                    ForEach(store.snapshot.dishes.filter { $0.restaurantID == restaurant.id }) { dish in
                                        HStack(spacing: 12) {
                                            if let photoURL = store.photoURL(for: dish.photoPath) {
                                                Button { previewPhoto = DishPhotoPreview(url: photoURL) } label: {
                                                    DishPhotoThumbnail(url: photoURL, height: 52)
                                                        .frame(width: 68)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            Text(dish.name)
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button("删除", role: .destructive) { deleteRestaurant(restaurant) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal).navigationTitle("吃什么")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingAdd) { AddFoodView() }
            .fullScreenCover(item: $previewPhoto) { preview in
                DishPhotoPreviewView(url: preview.url)
            }
        }
    }

    private func spin() {
        store.snapshot.dishSkips.removeAll { !Calendar.current.isDateInToday($0.date) }
        let candidates = FoodSelector.candidates(
            dishes: store.snapshot.dishes,
            profile: store.snapshot.profile,
            meals: store.snapshot.meals,
            skips: store.snapshot.dishSkips,
            avoidSameDayRepeat: store.snapshot.avoidRecentMeals
        )
        picked = candidates.randomElement()
        if picked == nil { store.banner = "没有符合禁忌条件且今天尚未出现的菜品" }
    }

    private func confirmPicked(_ dish: Dish) {
        let restaurant = store.snapshot.restaurants.first { $0.id == dish.restaurantID }
        store.snapshot.meals.append(
            .init(dishID: dish.id, dishName: dish.name, restaurantName: restaurant?.name ?? "")
        )
        picked = nil
        store.banner = "已记录本餐：\(dish.name)"
    }

    private func reroll(_ dish: Dish) {
        store.snapshot.dishSkips.append(.init(dishID: dish.id))
        picked = nil
        spin()
    }

    private func deleteRestaurant(_ restaurant: Restaurant) {
        if picked?.restaurantID == restaurant.id { picked = nil }
        store.deleteRestaurant(id: restaurant.id)
    }
}

private struct DishPhotoPreview: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DishPhotoThumbnail: View {
    let url: URL
    let height: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DishPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ContentUnavailableView("无法预览图片", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding()
            .accessibilityLabel("关闭图片预览")
        }
    }
}

struct AddFoodView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var category = "食堂"
    @State private var restaurant = ""
    @State private var dish = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoadingPhoto = false
    @State private var formError: String?

    private var draft: FoodEntryDraft {
        FoodEntryDraft(restaurantName: restaurant, dishName: dish, category: category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("餐厅") {
                    TextField("餐厅名称", text: $restaurant)
                        .textInputAutocapitalization(.never)
                    Picker("分类", selection: $category) {
                        ForEach(["食堂", "学校周边", "商场", "其他"], id: \.self) { Text($0) }
                    }
                }

                Section("菜品") {
                    TextField("菜品名称", text: $dish)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if isLoadingPhoto {
                            HStack { ProgressView(); Text("正在读取照片…") }
                        } else {
                            Label(photoData == nil ? "添加菜品照片（可选）" : "已选择菜品照片", systemImage: "photo")
                        }
                    }
                    .disabled(isLoadingPhoto)
                    .onChange(of: photoItem) { _, item in loadPhoto(item) }
                    if photoData != nil {
                        Button("移除照片", role: .destructive) {
                            photoItem = nil
                            photoData = nil
                        }
                    }
                }

                if let formError {
                    Section { Text(formError).foregroundStyle(.red) }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("添加餐厅和菜品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!draft.isValid || isLoadingPhoto)
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        formError = nil
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    formError = "无法读取这张照片，请重新选择。"
                    return
                }
                photoData = data
            } catch {
                formError = "照片读取失败：\(error.localizedDescription)"
            }
        }
    }

    private func save() {
        guard draft.isValid else { return }
        formError = nil
        do {
            let photoPath = try photoData.map { try store.addDishPhoto(data: $0) }
            let newRestaurant = Restaurant(name: draft.restaurantName, category: draft.category)
            store.snapshot.restaurants.append(newRestaurant)
            store.snapshot.dishes.append(
                .init(restaurantID: newRestaurant.id, name: draft.dishName, photoPath: photoPath)
            )
            store.banner = "已添加 \(draft.dishName)"
            dismiss()
        } catch {
            formError = "照片保存失败：\(error.localizedDescription)"
        }
    }
}
