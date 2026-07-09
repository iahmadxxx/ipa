import SwiftUI

struct InsightsView: View { @State private var data:InsightsResponse?;@State private var error:String?;var body:some View{ScrollView{VStack(spacing:14){if let d=data{InsightCard(icon:"⚡️",title:"الجاهزية",text:d.readiness);InsightCard(icon:"🎯",title:"خطة اليوم",text:d.todayPlan);InsightCard(icon:"🚀",title:"التقدم",text:d.progress);InsightCard(icon:"⚖️",title:"توازن العضلات",text:d.balance);InsightCard(icon:"🧠",title:"اقتراح الأوزان",text:d.nextWeights);InsightCard(icon:"📈",title:"التقرير الأسبوعي",text:d.weeklyReport)}else{ProgressView("جاري التحليل…").padding(.top,70)};if let error{Text(error).foregroundStyle(.red)}}.padding()}.navigationTitle("التحليلات").task{await load()}.refreshable{await load()} }
    private func load()async{do{data=try await APIClient.shared.insights()}catch{self.error=error.localizedDescription}}
}
struct InsightCard: View {let icon,title,text:String;init(icon:String,title:String,text:String){self.icon=icon;self.title=title;self.text=text};var body:some View{Card{HStack{Text(icon).font(.title2);Text(title).font(.headline)};Text(text).font(.subheadline).padding(.top,5).textSelection(.enabled)}}}
