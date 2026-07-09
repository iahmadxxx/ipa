import SwiftUI

struct HomeView: View {
    @State private var dashboard: Dashboard?; @State private var loading = false; @State private var error: String?; @State private var selectedDate = Date()
    var body: some View { ScrollView { VStack(spacing:14) {
        HStack { VStack(alignment:.leading){ Text("صباح الخير يا أحمد").font(.title2.bold()); Text("بياناتك الصحية والرياضية في مكان واحد").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button { Task { await load() } } label: { Image(systemName:"arrow.clockwise").font(.title3) }.disabled(loading) }
        DatePicker("التاريخ", selection:$selectedDate, in: ...Date(), displayedComponents:.date).datePickerStyle(.compact).onChange(of:selectedDate){ Task { await load() } }
        if let d = dashboard {
            HStack(spacing:10){ MetricCard(icon:"⚡️", title:"الجاهزية", value: readinessScore(d.readiness)); MetricCard(icon:"❤️", title:"النبض الآن", value: d.currentHR.map{"\($0) BPM"} ?? "—") }
            HStack(spacing:10){ MetricCard(icon:"💤", title:"نبض الراحة", value:d.restingHR.map{"\($0) BPM"} ?? "—"); MetricCard(icon:"😴", title:"النوم", value:minutes(d.sleepMinutes)) }
            HStack(spacing:10){ MetricCard(icon:"🚶", title:"الخطوات", value:d.steps.map{ $0.formatted() } ?? "—"); MetricCard(icon:"🔥", title:"السعرات", value:d.calories.map{"\($0)"} ?? "—") }
            Card { Label("خطة اليوم", systemImage:"target").font(.headline); Text(d.todayPlan).font(.subheadline).padding(.top,4).textSelection(.enabled) }
            Card { Label("تفاصيل الجاهزية", systemImage:"bolt.heart.fill").font(.headline); Text(d.readiness).font(.subheadline).padding(.top,4).textSelection(.enabled) }
        } else if loading { ProgressView("جاري التحديث…").padding(.top,60) }
        if let error { Text(error).foregroundStyle(.red).font(.footnote) }
    }.padding() }.navigationTitle("FitbitAir").refreshable { await load() }.task { await load() } }
    private func load() async { loading = true; error = nil; do { let fmt = DateFormatter(); fmt.dateFormat="yyyy-MM-dd"; dashboard = try await APIClient.shared.dashboard(date: fmt.string(from:selectedDate)) } catch { self.error = error.localizedDescription }; loading=false }
    private func minutes(_ v:Int?)->String { guard let v else{return "—"}; return "\(v/60)س \(v%60)د" }
    private func readinessScore(_ t:String)->String { let p=t.components(separatedBy:CharacterSet.decimalDigits.inverted).first{$0.count>=2}; return p.map{"\($0)/100"} ?? "جاهز" }
}
