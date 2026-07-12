import SwiftUI
import UIKit
import VisionKit

struct WellnessView: View {
    @State private var section = 0

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Picker("القسم", selection: $section) {
                    Text("التغذية").tag(0)
                    Text("تطور الجسم").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.top, 10)

                if section == 0 {
                    NutritionDashboardView()
                } else {
                    BodyProgressView()
                }
            }
        }
        .navigationTitle("التغذية والتقدم")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Nutrition dashboard

private struct NutritionDashboardView: View {
    @State private var data: NutritionDayResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var editorDraft: FoodDraft?
    @State private var showScanner = false
    @State private var photoMode: FoodPhotoMode?
    @State private var capturedImage: UIImage?
    @State private var analyzing = false
    @State private var scannerMessage: String?
    @State private var showSavedFoods = false
    @State private var copyingYesterday = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let error { ErrorBanner(message: error) }

                if loading && data == nil {
                    LoadingStateView(text: "جاري تحميل سجل اليوم...")
                } else {
                    header
                    actionGrid
                    entriesSection
                    safetyNote
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editorDraft) { draft in
            FoodEditorView(draft: draft) { savedDraft in
                Task { await save(savedDraft) }
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                BarcodeScannerView { code in
                    showScanner = false
                    Task { await lookup(code) }
                }
                .navigationTitle("مسح الباركود")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إغلاق") { showScanner = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showSavedFoods) {
            SavedProductsPicker { product in
                showSavedFoods = false
                editorDraft = FoodDraft(savedProduct: product)
            }
        }
        .sheet(item: $photoMode) { mode in
            CameraPicker { image in
                photoMode = nil
                guard let image else { return }
                capturedImage = image
                Task { await analyze(image, mode: mode) }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if analyzing {
                ZStack {
                    Color.black.opacity(0.58).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(FitTheme.accent).scaleEffect(1.2)
                        Text("Gemini يحلل الصورة...")
                            .font(.headline)
                        Text("بتشوف النتيجة وتراجعها قبل الحفظ")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(28)
                    .background(FitTheme.backgroundSoft, in: RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .alert("الباركود", isPresented: Binding(
            get: { scannerMessage != nil },
            set: { if !$0 { scannerMessage = nil } }
        )) {
            Button("تصوير جدول القيم") { photoMode = .nutritionLabel }
            Button("إغلاق", role: .cancel) {}
        } message: {
            Text(scannerMessage ?? "")
        }
        .alert("FitbitAir", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("تم", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ملخص اليوم")
                        .font(.title2.bold())
                    Text(data?.date ?? "اليوم")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                ZStack {
                    Circle().fill(FitTheme.accent.opacity(0.16)).frame(width: 58, height: 58)
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(FitTheme.accent)
                }
            }

            GlassCard(padding: 14) {
                VStack(spacing: 14) {
                    macroProgress(
                        title: "السعرات",
                        value: data?.totals.calories ?? 0,
                        goal: data?.goals.calories,
                        unit: "سعرة",
                        tint: FitTheme.accent
                    )
                    macroProgress(title: "البروتين", value: data?.totals.protein ?? 0, goal: data?.goals.protein, unit: "غ", tint: FitTheme.accentBlue)
                    macroProgress(title: "الكارب", value: data?.totals.carbs ?? 0, goal: data?.goals.carbs, unit: "غ", tint: FitTheme.warning)
                    macroProgress(title: "الدهون", value: data?.totals.fat ?? 0, goal: data?.goals.fat, unit: "غ", tint: FitTheme.accentPurple)
                }
            }
        }
    }

    private func macroProgress(title: String, value: Double, goal: Double?, unit: String, tint: Color) -> some View {
        let progress = min(1, value / max(1, goal ?? value))
        return VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(goal == nil ? "\(value.clean) \(unit)" : "\(value.clean) / \((goal ?? 0).clean) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
        }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "إضافة الطعام", subtitle: "كل نتيجة تظهر لك قبل الحفظ")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                foodAction(icon: "barcode.viewfinder", title: "مسح باركود", subtitle: "للمنتجات المغلفة", tint: FitTheme.accent) {
                    showScanner = true
                }
                foodAction(icon: "camera.viewfinder", title: "تصوير وجبة", subtitle: "تقدير قابل للتعديل", tint: FitTheme.accentBlue) {
                    photoMode = .meal
                }
                foodAction(icon: "doc.text.viewfinder", title: "جدول القيم", subtitle: "إذا المنتج غير موجود", tint: FitTheme.warning) {
                    photoMode = .nutritionLabel
                }
                foodAction(icon: "square.and.pencil", title: "إدخال يدوي", subtitle: "أدخل القيم بنفسك", tint: FitTheme.accentPurple) {
                    editorDraft = .empty
                }
                foodAction(icon: "heart.text.square.fill", title: "الأطعمة المحفوظة", subtitle: "المفضلة والمنتجات السابقة", tint: FitTheme.positive) {
                    showSavedFoods = true
                }
                foodAction(icon: "doc.on.doc.fill", title: copyingYesterday ? "جاري النسخ" : "نسخ أكل أمس", subtitle: "إضافة وجبات أمس لليوم", tint: FitTheme.warning) {
                    Task { await copyYesterday() }
                }
            }
        }
    }

    private func foodAction(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.52)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "وجبات اليوم", subtitle: "\(data?.entries.count ?? 0) عنصر")
            if data?.entries.isEmpty != false {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.system(size: 34))
                            .foregroundStyle(FitTheme.accent)
                        Text("ما سجلت أكل اليوم")
                            .font(.headline)
                        Text("امسح الباركود أو صوّر وجبتك وراجع الأرقام قبل الحفظ.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(mealGroups, id: \.0) { group in
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(mealTitle(group.0))
                                .font(.headline)
                                .foregroundStyle(FitTheme.accent)
                            ForEach(group.1) { entry in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name).font(.subheadline.weight(.semibold))
                                        Text("\(entry.calories.clean) سعرة • P \(entry.protein.clean) • C \(entry.carbs.clean) • F \(entry.fat.clean)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.56))
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await delete(entry) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(FitTheme.danger)
                                            .padding(8)
                                    }
                                }
                                if entry.id != group.1.last?.id { Divider().overlay(Color.white.opacity(0.08)) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(FitTheme.positive)
            Text("نتائج الصور تقديرية. التطبيق ما يحفظ أي وجبة إلا بعد ما تراجع الأرقام وتضغط حفظ.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.top, 4)
    }

    private var mealGroups: [(String, [NutritionEntry])] {
        let entries = data?.entries ?? []
        return ["breakfast", "lunch", "dinner", "snack"].compactMap { type in
            let rows = entries.filter { $0.mealType == type }
            return rows.isEmpty ? nil : (type, rows)
        }
    }

    private func mealTitle(_ key: String) -> String {
        switch key {
        case "breakfast": return "الفطور"
        case "lunch": return "الغداء"
        case "dinner": return "العشاء"
        default: return "السناك"
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await APIClient.shared.nutritionDay()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func save(_ draft: FoodDraft) async {
        do {
            data = try await APIClient.shared.addNutritionEntry(
                mealType: draft.mealType,
                name: draft.name,
                calories: draft.calories,
                protein: draft.protein,
                carbs: draft.carbs,
                fat: draft.fat,
                quantity: draft.quantityGrams,
                servingDescription: draft.servingDescription,
                source: draft.source,
                barcode: draft.barcode
            )
            editorDraft = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ entry: NutritionEntry) async {
        do {
            try await APIClient.shared.deleteNutritionEntry(id: entry.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func lookup(_ code: String) async {
        analyzing = true
        defer { analyzing = false }
        do {
            let result = try await APIClient.shared.lookupBarcode(code)
            if let p = result.product, result.found {
                editorDraft = FoodDraft(product: p)
            } else {
                scannerMessage = result.message ?? "المنتج غير موجود. صوّر جدول القيم الغذائية."
            }
        } catch {
            scannerMessage = error.localizedDescription
        }
    }

    @MainActor
    private func copyYesterday() async {
        guard !copyingYesterday else { return }
        copyingYesterday = true
        defer { copyingYesterday = false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Qatar") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar")
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = formatter.string(from: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        do {
            let oldDay = try await APIClient.shared.nutritionDay(date: yesterday)
            guard !oldDay.entries.isEmpty else {
                statusMessage = "ما فيه أكل مسجل أمس."
                return
            }
            var latest = data
            for entry in oldDay.entries {
                latest = try await APIClient.shared.addNutritionEntry(
                    mealType: entry.mealType,
                    name: entry.name,
                    calories: entry.calories,
                    protein: entry.protein,
                    carbs: entry.carbs,
                    fat: entry.fat,
                    quantity: max(1, entry.quantity),
                    servingDescription: entry.servingDescription,
                    source: "copied"
                )
            }
            data = latest
            statusMessage = "تم نسخ \(oldDay.entries.count) عناصر من أكل أمس."
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func analyze(_ image: UIImage, mode: FoodPhotoMode) async {
        guard let base64 = image.fitbitBase64(maxDimension: 1280, quality: 0.68) else {
            error = "تعذر تجهيز الصورة"
            return
        }
        analyzing = true
        defer { analyzing = false }
        do {
            let response = try await APIClient.shared.analyzeFoodImage(base64, mode: mode.rawValue)
            editorDraft = FoodDraft(analysis: response.analysis, source: mode == .meal ? "ai_meal" : "ai_label")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum FoodPhotoMode: String, Identifiable {
    case meal
    case nutritionLabel = "label"
    var id: String { rawValue }
}

private struct FoodDraft: Identifiable {
    let id = UUID()
    var name: String
    var mealType: String
    var servingDescription: String
    var quantityGrams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var source: String
    var barcode: String?
    var notes: String
    var caloriesPer100: Double?
    var proteinPer100: Double?
    var carbsPer100: Double?
    var fatPer100: Double?

    static let empty = FoodDraft(
        name: "", mealType: "snack", servingDescription: "", quantityGrams: 100,
        calories: 0, protein: 0, carbs: 0, fat: 0,
        source: "manual", barcode: nil, notes: "",
        caloriesPer100: nil, proteinPer100: nil, carbsPer100: nil, fatPer100: nil
    )

    init(product: FoodProduct) {
        let grams = max(1, product.servingGrams ?? 100)
        let factor = grams / 100
        name = [product.brand, product.name].compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }.joined(separator: " - ")
        mealType = "snack"
        servingDescription = "\(grams.formatted(.number.precision(.fractionLength(0...1)))) غ"
        quantityGrams = grams
        calories = product.calories * factor
        protein = product.protein * factor
        carbs = product.carbs * factor
        fat = product.fat * factor
        source = product.source
        barcode = product.barcode
        notes = "تم حساب القيم حسب الكمية. غيّر الجرامات وسيعاد الحساب تلقائيًا."
        caloriesPer100 = product.calories
        proteinPer100 = product.protein
        carbsPer100 = product.carbs
        fatPer100 = product.fat
    }

    init(savedProduct product: FA2FoodProduct) {
        let grams = max(1, product.servingGrams ?? 100)
        let factor = grams / 100
        name = [product.brand, product.name].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " - ")
        mealType = "snack"
        servingDescription = "\(grams.formatted(.number.precision(.fractionLength(0...1)))) غ"
        quantityGrams = grams
        calories = product.caloriesPer100 * factor
        protein = product.proteinPer100 * factor
        carbs = product.carbsPer100 * factor
        fat = product.fatPer100 * factor
        source = product.source
        barcode = product.barcode
        notes = "منتج محفوظ. غيّر الكمية وسيعاد حساب القيم تلقائيًا."
        caloriesPer100 = product.caloriesPer100
        proteinPer100 = product.proteinPer100
        carbsPer100 = product.carbsPer100
        fatPer100 = product.fatPer100
    }

    init(analysis: FoodImageAnalysis, source: String) {
        name = analysis.name
        mealType = analysis.mealType
        servingDescription = analysis.servingDescription ?? ""
        quantityGrams = max(1, analysis.quantityGrams)
        calories = analysis.calories
        protein = analysis.protein
        carbs = analysis.carbs
        fat = analysis.fat
        self.source = source
        barcode = nil
        notes = "الثقة: \(analysis.confidence) • \(analysis.notes)"
        if source == "ai_label" {
            caloriesPer100 = analysis.calories
            proteinPer100 = analysis.protein
            carbsPer100 = analysis.carbs
            fatPer100 = analysis.fat
        } else {
            caloriesPer100 = nil
            proteinPer100 = nil
            carbsPer100 = nil
            fatPer100 = nil
        }
    }

    private init(
        name: String, mealType: String, servingDescription: String, quantityGrams: Double,
        calories: Double, protein: Double, carbs: Double, fat: Double,
        source: String, barcode: String?, notes: String,
        caloriesPer100: Double?, proteinPer100: Double?, carbsPer100: Double?, fatPer100: Double?
    ) {
        self.name = name
        self.mealType = mealType
        self.servingDescription = servingDescription
        self.quantityGrams = quantityGrams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.source = source
        self.barcode = barcode
        self.notes = notes
        self.caloriesPer100 = caloriesPer100
        self.proteinPer100 = proteinPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
    }

    mutating func recalculateForQuantity() {
        guard let caloriesPer100, let proteinPer100, let carbsPer100, let fatPer100 else { return }
        let grams = max(1, min(5000, quantityGrams))
        let factor = grams / 100
        calories = caloriesPer100 * factor
        protein = proteinPer100 * factor
        carbs = carbsPer100 * factor
        fat = fatPer100 * factor
        servingDescription = "\(grams.formatted(.number.precision(.fractionLength(0...1)))) غ"
    }
}

private struct FoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: FoodDraft
    let onSave: (FoodDraft) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section("المنتج أو الوجبة") {
                        TextField("الاسم", text: $draft.name)
                        Picker("الوجبة", selection: $draft.mealType) {
                            Text("الفطور").tag("breakfast")
                            Text("الغداء").tag("lunch")
                            Text("العشاء").tag("dinner")
                            Text("سناك").tag("snack")
                        }
                        TextField("وصف الحصة", text: $draft.servingDescription)
                        HStack {
                            Text("الكمية")
                            Spacer()
                            TextField("100", value: $draft.quantityGrams, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("غ").foregroundStyle(.secondary)
                        }
                    }
                    Section("القيم للحصة التي أكلتها") {
                        macroField("السعرات", value: $draft.calories, unit: "kcal")
                        macroField("البروتين", value: $draft.protein, unit: "g")
                        macroField("الكارب", value: $draft.carbs, unit: "g")
                        macroField("الدهون", value: $draft.fat, unit: "g")
                    }
                    if !draft.notes.isEmpty {
                        Section("مراجعة") {
                            Text(draft.notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: draft.quantityGrams) { _, _ in
                    draft.recalculateForQuantity()
                }
            }
            .navigationTitle("مراجعة قبل الحفظ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { onSave(draft) }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func macroField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private struct SavedProductsPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [FA2FoodProduct] = []
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var loading = true
    @State private var error: String?
    let onSelect: (FA2FoodProduct) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Toggle("المفضلة فقط", isOn: $favoritesOnly)
                            .tint(FitTheme.accent)
                            .padding(14)
                            .background(FitTheme.card, in: RoundedRectangle(cornerRadius: 16))

                        if loading {
                            ProgressView("جاري تحميل المنتجات...")
                                .padding(.top, 50)
                        } else if let error {
                            ErrorBanner(message: error)
                        } else if products.isEmpty {
                            GlassCard {
                                Text("ما فيه منتجات محفوظة حتى الآن.")
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        } else {
                            ForEach(products) { product in
                                GlassCard(padding: 14) {
                                    HStack(spacing: 12) {
                                        Button {
                                            onSelect(product)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(product.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.white)
                                                if !product.brand.isEmpty {
                                                    Text(product.brand)
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.55))
                                                }
                                                Text("لكل 100غ: \(product.caloriesPer100.clean) سعرة • P \(product.proteinPer100.clean) • C \(product.carbsPer100.clean) • F \(product.fatPer100.clean)")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.white.opacity(0.58))
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            Task { await toggleFavorite(product) }
                                        } label: {
                                            Image(systemName: product.favorite ? "heart.fill" : "heart")
                                                .font(.title3)
                                                .foregroundStyle(product.favorite ? FitTheme.danger : .white.opacity(0.5))
                                                .padding(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .refreshable { await load() }
            }
            .navigationTitle("الأطعمة المحفوظة")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "ابحث بالاسم أو الباركود")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: favoritesOnly) { _, _ in Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            products = try await APIClient.shared.fa2Products(query: query, favorites: favoritesOnly)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFavorite(_ product: FA2FoodProduct) async {
        do {
            try await APIClient.shared.fa2FavoriteProduct(id: product.id, favorite: !product.favorite)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Barcode and camera

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            return UIHostingController(rootView: ContentUnavailableView(
                "الماسح غير متاح",
                systemImage: "barcode.viewfinder",
                description: Text("استخدم تصوير جدول القيم الغذائية بدلًا منه.")
            ))
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        DispatchQueue.main.async {
            try? controller.startScanning()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, !code.isEmpty {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(code)
                    break
                }
            }
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { self.onFinish(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onFinish(nil) }
        }
    }
}

// MARK: - Body progress photos

struct BodyProgressView: View {
    @State private var photos: [BodyPhotoEntry] = []
    @State private var selected: Set<UUID> = []
    @State private var showCapture = false
    @State private var analysis: BodyProgressAnalysis?
    @State private var loading = false
    @State private var error: String?

    private let store = BodyPhotoStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                introCard
                if let error { ErrorBanner(message: error) }
                captureGuide
                photoGrid
                analysisControls
                if let analysis { analysisCard(analysis) }
                privacyCard
            }
            .padding(18)
            .padding(.bottom, 34)
        }
        .task {
            photos = store.loadEntries()
            await loadSavedAnalysis()
        }
        .sheet(isPresented: $showCapture) {
            BodyPhotoCaptureView { pose, image in
                do {
                    try store.save(image: image, pose: pose)
                    photos = store.loadEntries()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        .overlay {
            if loading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(FitTheme.accent)
                        Text("جاري مقارنة صور التطور...").font(.headline)
                    }
                    .padding(26)
                    .background(FitTheme.backgroundSoft, in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }
    }

    private var introCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(FitTheme.accent.opacity(0.16)).frame(width: 58, height: 58)
                    Image(systemName: "figure.arms.open").font(.system(size: 27)).foregroundStyle(FitTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("صور تطور جسمك").font(.title3.bold())
                    Text("اختر صورًا قديمة وحديثة، وGemini يقارن التغير المرئي بعد موافقتك.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var captureGuide: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("تصوير ثابت = مقارنة أفضل").font(.headline)
                    Spacer()
                    Button {
                        showCapture = true
                    } label: {
                        Label("تصوير", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FitTheme.accent)
                    .foregroundStyle(.black)
                }
                Text("نفس المكان، الإضاءة، المسافة، الوقت والوضعية. صوّر أمامي وجانبي وخلفي.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    @ViewBuilder
    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "الصور المحفوظة على الآيفون", subtitle: "حدد صورتين أو أكثر من نفس الوضعية للمقارنة")
            if photos.isEmpty {
                GlassCard {
                    Text("ما فيه صور حتى الآن. اضغط تصوير وابدأ أول متابعة.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(photos) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else if selected.count < 6 { selected.insert(item.id) }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                if let image = store.image(for: item) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    RoundedRectangle(cornerRadius: 16).fill(FitTheme.card).frame(height: 150)
                                }
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(item.id) ? FitTheme.accent : .white.opacity(0.75))
                                    .padding(7)
                                VStack {
                                    Spacer()
                                    Text(item.pose.title)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(.black.opacity(0.65), in: Capsule())
                                        .padding(7)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("حذف الصورة", role: .destructive) {
                                store.delete(item)
                                selected.remove(item.id)
                                photos = store.loadEntries()
                            }
                        }
                    }
                }
            }
        }
    }

    private var analysisControls: some View {
        VStack(spacing: 10) {
            Button {
                Task { await analyzeSelected() }
            } label: {
                Label("تحليل الصور المحددة (\(selected.count))", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.count < 2 || loading)

            Text("يتم إرسال الصور المحددة فقط عند الضغط على التحليل. لا تُحفظ الصور في Railway؛ يحفظ التقرير النصي فقط.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    private func analysisCard(_ item: BodyProgressAnalysis) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(FitTheme.accent)
                    Text("تحليل التطور").font(.title3.bold())
                    Spacer()
                    Text(item.confidence).font(.caption.bold()).foregroundStyle(FitTheme.warning)
                }
                analysisLine("الخلاصة", item.summary)
                analysisLine("التغيرات المرئية", item.waistChange)
                analysisLine("مناطق ظهر فيها تحسن", item.upperBody)
                analysisLine("مناطق تحتاج تركيز", item.lowerBody)
                analysisLine("ثبات الإضاءة والوضعية", item.posture)
                analysisLine("التقدير البصري", item.estimatedChange)
                analysisLine("ملاحظات", item.notes)
            }
        }
    }

    private func analysisLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(FitTheme.accent)
            Text(value.isEmpty ? "غير واضح من الصور" : value)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(FitTheme.positive)
            Text("التحليل بصري وتقديري وليس قياسًا طبيًا أو نسبة دهون مؤكدة. صورك الأصلية تبقى داخل التطبيق على جهازك.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    @MainActor
    private func loadSavedAnalysis() async {
        do {
            let progress = try await APIClient.shared.fa2BodyProgress()
            guard analysis == nil, let latest = progress.analyses.first else { return }
            analysis = BodyProgressAnalysis(
                id: latest.id,
                summary: latest.summary,
                waistChange: latest.visibleChanges.joined(separator: "، "),
                upperBody: latest.areasImproved.joined(separator: "، "),
                lowerBody: latest.areasToFocus.joined(separator: "، "),
                posture: latest.photoConsistency ?? "",
                estimatedChange: latest.estimatedBodyFatRange ?? "",
                confidence: latest.confidence ?? "متوسط",
                notes: "آخر تحليل محفوظ بتاريخ \(latest.analysisDate). التحليل بصري وتقديري.",
                createdAt: latest.createdAt
            )
        } catch {
            // الصور المحلية تظل قابلة للاستخدام حتى لو تعذر تحميل التقرير السابق.
        }
    }

    @MainActor
    private func analyzeSelected() async {
        let chosen = photos.filter { selected.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        guard chosen.count >= 2 else { return }
        guard Set(chosen.map { $0.pose.rawValue }).count == 1 else {
            error = "اختر صورًا من نفس الوضعية فقط: أمامي أو جانبي أو خلفي."
            return
        }
        let dateFormatter = ISO8601DateFormatter()
        var payload: [[String: String]] = []
        for item in chosen {
            if let image = store.image(for: item), let data = image.fitbitBase64(maxDimension: 900, quality: 0.55) {
                payload.append([
                    "mime_type": "image/jpeg",
                    "data": data,
                    "date": dateFormatter.string(from: item.createdAt),
                    "pose": item.pose.rawValue
                ])
            }
        }
        guard payload.count >= 2 else {
            error = "تعذر تجهيز الصور المحددة"
            return
        }
        loading = true
        defer { loading = false }
        do {
            analysis = try await APIClient.shared.analyzeBodyProgress(payload).analysis
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum BodyPose: String, Codable, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var title: String {
        switch self { case .front: return "أمامي"; case .side: return "جانبي"; case .back: return "خلفي" }
    }
}

private struct BodyPhotoEntry: Codable, Identifiable {
    let id: UUID
    let pose: BodyPose
    let fileName: String
    let createdAt: Date
}

private final class BodyPhotoStore {
    static let shared = BodyPhotoStore()
    private let fm = FileManager.default

    private var directory: URL {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("FitbitAirBodyProgress", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var manifest: URL { directory.appendingPathComponent("manifest.json") }

    func loadEntries() -> [BodyPhotoEntry] {
        guard let data = try? Data(contentsOf: manifest), let items = try? JSONDecoder.fitbit.decode([BodyPhotoEntry].self, from: data) else { return [] }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func image(for item: BodyPhotoEntry) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(item.fileName).path)
    }

    func save(image: UIImage, pose: BodyPose) throws {
        guard let data = image.fitbitJPEG(maxDimension: 1800, quality: 0.82) else {
            throw NSError(domain: "FitbitAir", code: 1, userInfo: [NSLocalizedDescriptionKey: "تعذر حفظ الصورة"])
        }
        var items = loadEntries()
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        items.append(BodyPhotoEntry(id: id, pose: pose, fileName: fileName, createdAt: Date()))
        try saveManifest(items)
    }

    func delete(_ item: BodyPhotoEntry) {
        try? fm.removeItem(at: directory.appendingPathComponent(item.fileName))
        try? saveManifest(loadEntries().filter { $0.id != item.id })
    }

    private func saveManifest(_ items: [BodyPhotoEntry]) throws {
        let data = try JSONEncoder.fitbit.encode(items)
        try data.write(to: manifest, options: .atomic)
    }
}

private struct BodyPhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pose: BodyPose = .front
    @State private var showCamera = false
    let onSave: (BodyPose, UIImage) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 22) {
                    Picker("الوضعية", selection: $pose) {
                        ForEach(BodyPose.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(FitTheme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [10]))
                        Image(systemName: pose == .side ? "figure.stand" : "figure.arms.open")
                            .font(.system(size: 150, weight: .ultraLight))
                            .foregroundStyle(FitTheme.accent.opacity(0.48))
                    }
                    .frame(height: 390)

                    Text("خل جسمك داخل الإطار، وقف بنفس المسافة والإضاءة في كل مرة.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)

                    Button {
                        showCamera = true
                    } label: {
                        Label("فتح الكاميرا", systemImage: "camera.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(20)
            }
            .navigationTitle("صورة تقدم جديدة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image {
                        onSave(pose, image)
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

private extension UIImage {
    func fitbitJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = min(1, maxDimension / max(1, longest))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }

    func fitbitBase64(maxDimension: CGFloat, quality: CGFloat) -> String? {
        fitbitJPEG(maxDimension: maxDimension, quality: quality)?.base64EncodedString()
    }
}

private extension Double {
    var clean: String {
        if rounded() == self { return String(Int(self)) }
        return String(format: "%.1f", self)
    }
}

private extension JSONEncoder {
    static var fitbit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var fitbit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
