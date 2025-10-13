import Combine
import Foundation
import SwiftUI
import UserNotifications

// 定义任务状态
enum ReminderStatus: String, Codable {
    case pending = "待完成"  // 任务创建后的初始状态（非计数）
    case inProgress = "进行中"  // 计数任务的初始状态
    case completed = "已完成"
}

struct ReminderItem: Identifiable, Codable {
    // 1. 【数据模型】定义您的提醒事项的结构
    let id: UUID
    var name: String
    var account: String
    var description: String
    var nextDueDate: Date
    var recurrence: String

    // 🚀 新增属性
    var status: ReminderStatus
    var targetCount: Int  // 目标完成次数 (例如 5 次刷卡)
    var currentCount: Int  // 当前已完成次数 (例如 3/5)

    // 初始化方法也要相应更新
    init(
        id: UUID = UUID(),
        name: String,
        account: String,
        description: String,
        nextDueDate: Date,
        recurrence: String,
        targetCount: Int = 1,  // 默认为 1
        currentCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.account = account
        self.description = description
        self.nextDueDate = nextDueDate
        self.recurrence = recurrence
        self.targetCount = targetCount
        self.currentCount = currentCount

        // 根据 targetCount 自动设置初始状态
        if targetCount > 1 {
            self.status = .inProgress
        } else {
            self.status = .pending
        }
    }
}
// 2. 【数据管理器】用于存储和管理提醒事项的列表
class ReminderManager: ObservableObject {
    @Published var reminders: [ReminderItem] = [] {
        //  当 reminders 数组发生变化时，自动调用 save()
        didSet {
            save()
        }
    }

    // 初始化时调用加载方法
    init() {
        load()

        // 🚀 在管理器初始化时请求通知权限
        requestNotificationPermission()

        // 如果是第一次运行，列表为空，则加载初始示例数据
        if reminders.isEmpty {
            loadInitialExampleReminders()
        }
    }

    // 【加载数据】从 UserDefaults 读取并解码
    func load() {
        if let savedData = UserDefaults.standard.data(forKey: "Reminders") {
            if let decodedReminders = try? JSONDecoder().decode(
                [ReminderItem].self,
                from: savedData
            ) {
                reminders = decodedReminders
                return
            }
        }
        // 如果没有保存的数据，初始化一个空数组
        reminders = []
    }

    // 🚀 【保存数据】将 reminders 数组编码并写入 UserDefaults
    func save() {
        if let encodedData = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(encodedData, forKey: "Reminders")
        }
    }

    // 初始示例数据 (仅在第一次运行时显示)
    func loadInitialExampleReminders() {
        // ... (保持您之前硬编码的 Marriott 和 Credit Card 示例代码不变)
        let today = Date()
        let marriottReminder = ReminderItem(
            name: "万豪免房券使用提醒",
            account: "Marriott 账户",
            description: "请在券到期前检查使用。每年3月自动发券。",
            nextDueDate: Calendar.current.date(
                byAdding: .month,
                value: 5,
                to: today
            )!,
            recurrence: "每年重复",
            targetCount: 1  // 🚀 默认是 1
        )
        let ccReminder = ReminderItem(
            name: "信用卡消费达标提醒",
            account: "Chase 联名卡",
            description: "本账单周期需完成5笔交易，请在周期开始时检查。",
            nextDueDate: Calendar.current.date(
                byAdding: .day,
                value: 3,
                to: today
            )!,
            recurrence: "每月初提醒",
            targetCount: 5,  // 🚀 目标为 5 次
            currentCount: 2  // 🚀 假设已经刷了 2 次
        )
        reminders.append(marriottReminder)
        reminders.append(ccReminder)
    }

    // 【新增/编辑】添加或更新提醒事项
    func addOrUpdate(reminder: ReminderItem) {
        cancelNotification(for: reminder)
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            // 如果找到匹配的 ID，则更新现有项目
            reminders[index] = reminder
        } else {
            // 否则，添加新项目
            reminders.append(reminder)
        }
        scheduleNotification(for: reminder)
    }

    // 【删除】
    func delete(offsets: IndexSet) {
        for index in offsets {
            let reminderToDelete = reminders[index]
            // 🚀 删除前，先取消关联的通知
            cancelNotification(for: reminderToDelete)
        }
        reminders.remove(atOffsets: offsets)
    }

    // 【功能演示】模拟新增一个提醒事项
    func addExampleReminder() {
        let nextWeek = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: Date()
        )!
        let newReminder = ReminderItem(
            name: "新卡开卡礼消费提醒",
            account: "Amex Platinum",
            description: "开卡后3个月内需消费 $6000 达标。",
            nextDueDate: nextWeek,
            recurrence: "短期任务"
        )
        reminders.append(newReminder)
    }

    func scheduleNotification(for reminder: ReminderItem) {
        let center = UNUserNotificationCenter.current()

        // 1. 定义通知的内容
        let content = UNMutableNotificationContent()
        content.title = "⏰ 提醒事项：\(reminder.name)"
        content.body = "账户：\(reminder.account)。描述：\(reminder.description)"
        content.sound = UNNotificationSound.default  // 默认通知声音

        // 2. 定义触发器 (Trigger)
        // 💡 这里的关键是使用 reminder.nextDueDate 来设置通知时间

        // 获取提醒事项的日期组件 (年、月、日、时、分)
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.nextDueDate
        )

        // UNCalendarNotificationTrigger 会在指定时间触发通知
        // repeats: true 可以用于年/月重复，但设置年度重复需要额外的复杂逻辑来计算下一个日期。
        // 为了简化，我们只设置一次，并在用户标记完成后重新设置。
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        // 3. 定义请求
        // ⚠️ 使用 reminder.id.uuidString 作为唯一标识符，以便后续更新或取消
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )

        // 4. 安排通知
        center.add(request) { error in
            if let error = error {
                print("设置通知失败: \(error.localizedDescription)")
            } else {
                print("通知已成功安排，ID: \(reminder.id.uuidString)")
            }
        }
    }

    func completeTask(item: ReminderItem) {
        // 1. 找到在数组中的索引
        guard let index = reminders.firstIndex(where: { $0.id == item.id })
        else { return }

        // 2. 将状态设置为完成
        reminders[index].status = .completed

        // 3. ⚠️ 如果任务是重复的，您需要在**这里**计算下一个到期日并更新 nextDueDate
        //    (现在暂不实现，留作下一步)

        // 4. 清理通知（如果已完成，就不再提醒了）
        cancelNotification(for: item)
    }

    func incrementCount(item: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id })
        else { return }

        // 1. 增加当前计数
        let newCount = reminders[index].currentCount + 1
        reminders[index].currentCount = newCount

        // 2. 检查是否达标
        if newCount >= reminders[index].targetCount {
            // 如果达标，调用 completeTask
            completeTask(item: reminders[index])
        }
    }
}

// 3. 【用户界面】主视图 ContentView
struct ContentView: View {
    // 声明数据管理器，@StateObject确保其生命周期与视图绑定
    @StateObject var manager = ReminderManager()
    @State private var isShowingAddView = false
    // 🚀 增加一个状态，用于存储正在被编辑的提醒事项
    @State private var editingReminder: ReminderItem?
    // 🚀 新增状态：控制视图显示“未完成”还是“已完成”
    @State private var selectedStatus: ReminderStatus = .pending

    // 🚀 计算属性：根据当前选择的状态过滤出要显示的列表
    var filteredReminders: [ReminderItem] {
        if selectedStatus == .completed {
            return manager.reminders.filter { $0.status == .completed }
        } else {
            // "待完成" 和 "进行中" 视为同一类：未完成
            return manager.reminders.filter { $0.status != .completed }
        }
    }

    var body: some View {
        // NavigationView (或 Swift 5.0+ 的 NavigationStack) 提供标题和工具栏
        NavigationView {

            // List 用于展示可滚动的列表数据
            List {
                // ForEach 循环遍历管理器中的所有提醒事项
                ForEach(manager.reminders) { item in

                    // 垂直堆栈，用于布局单个提醒事项的细节
                    VStack(alignment: .leading, spacing: 4) {

                        // 第一行：标题和重复规则
                        HStack {
                            Text(item.name)
                                .font(.headline)  // 粗体大字
                            Spacer()  // 推出右侧的重复规则
                            Text(item.recurrence)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // 第二行：账户和到期日
                        HStack {
                            Text("账户: \(item.account)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            // 日期格式化显示
                            Text(
                                "到期日: \(item.nextDueDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        }

                        // 第三行：详细描述
                        Text(item.description)
                            .font(.caption)
                            .lineLimit(1)  // 限制一行显示
                    }
                    .padding(.vertical, 4)  // 上下留白
                    // 🚀 【点击编辑】
                    .onTapGesture {
                        editingReminder = item
                    }
                }
                // 🚀 【滑动删除】
                .onDelete(perform: manager.delete)
            }
            // 列表的导航栏标题
            .navigationTitle("账户提醒事项")

            // 导航栏右上角的按钮
            .toolbar {
                // 点击按钮时，调用 manager 的方法添加一个新示例提醒
                Button {
                    isShowingAddView = true
                } label: {
                    Image(systemName: "plus.circle.fill")  // iOS 系统的加号图标
                }
            }
            .sheet(item: $editingReminder) { reminder in
                // 弹窗用于编辑现有项目
                AddReminderView(
                    onSave: { updatedReminder in  // 🚀 onSave 闭包作为第一个参数
                        manager.addOrUpdate(reminder: updatedReminder)
                    },
                    reminder: reminder
                )  // 🚀 reminder 作为第二个参数
            }
            .sheet(isPresented: $isShowingAddView) {
                // 弹窗用于添加新项目
                AddReminderView(
                    onSave: { newReminder in  // 🚀 onSave 闭包作为第一个参数
                        manager.addOrUpdate(reminder: newReminder)
                    },
                    reminder: ReminderItem(  // 🚀 reminder 作为第二个参数
                        name: "",
                        account: "",
                        description: "",
                        nextDueDate: Date(),
                        recurrence: "每年重复",
                        targetCount: 1,  // 🚀 新增：确保传入 targetCount
                        currentCount: 0  // 🚀 新增：确保传入 currentCount
                    )
                )
            }
        }
    }
}

// 新视图：用于输入新的提醒事项 或 编辑现有提醒事项
struct AddReminderView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (ReminderItem) -> Void

    // 🚀 传入一个完整的 ReminderItem，用于初始化表单
    @State var reminder: ReminderItem

    let recurrenceOptions = ["一次性任务", "每月初提醒", "每年重复", "自定义..."]

    var body: some View {
        NavigationView {
            Form {
                // ... (表单内容保持不变)
                Section(header: Text("核心信息")) {
                    TextField("提醒名称 (例如: 万豪房券)", text: $reminder.name)
                    TextField("关联账户 (例如: Marriott)", text: $reminder.account)
                }
                // --- 目标和频率 ---
                Section(header: Text("目标和频率")) {
                    // 🚀 新增：目标计数输入，绑定到 $reminder.targetCount
                    // 计数范围从 1 次到 20 次，如果任务是计数型，targetCount > 1
                    Stepper(
                        "目标次数: \(reminder.targetCount)",
                        value: $reminder.targetCount,
                        in: 1...20
                    )

                    // 频率选择器 (绑定到 $reminder.recurrence)
                    Picker("重复频率", selection: $reminder.recurrence) {
                        ForEach(recurrenceOptions, id: \.self) { option in
                            Text(option)
                        }
                    }
                }
                Section(header: Text("时间与频率")) {
                    DatePicker(
                        "下一个到期日",
                        selection: $reminder.nextDueDate,
                        displayedComponents: .date
                    )
                }
                Section(header: Text("详细描述")) {
                    TextEditor(text: $reminder.description)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(reminder.name.isEmpty ? "添加新提醒" : "编辑提醒")  // 根据名称判断标题
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        // 1. 确保在保存时，任务状态和 currentCount 逻辑正确
                        // 如果用户将目标次数从 5 改回 1，状态需要变回 .pending
                        if reminder.targetCount <= 1
                            && reminder.status != .completed
                        {
                            reminder.status = .pending
                        } else if reminder.targetCount > 1
                            && reminder.status != .completed
                        {
                            reminder.status = .inProgress
                            // 如果 targetCount 变大了，currentCount 不能超过 targetCount
                            if reminder.currentCount > reminder.targetCount {
                                reminder.currentCount = reminder.targetCount
                            }
                        }

                        // 2. 直接将修改后的 @State reminder 传回 ContentView
                        onSave(reminder)
                        dismiss()
                    }
                    .disabled(reminder.name.isEmpty || reminder.account.isEmpty)
                }
            }
        }
    }
}

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .badge, .sound,
    ]) { success, error in
        if success {
            print("通知权限已授权。")
        } else if let error = error {
            print("通知权限请求错误: \(error.localizedDescription)")
            // 💡 实际应用中，您可能需要提醒用户去设置中手动开启
        }
    }
}

// ⚠️ 额外添加：清理旧通知的方法（在编辑或删除时使用）
func cancelNotification(for reminder: ReminderItem) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: [reminder.id.uuidString])
    print("已取消旧通知: \(reminder.id.uuidString)")
}

#Preview {
    ContentView()
}
