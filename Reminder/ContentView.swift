import Combine
import Foundation
import SwiftUI

// 定义任务状态
enum ReminderStatus: String, Codable {
    case pending = "待完成"  // 任务创建后的初始状态（非计数）
    case inProgress = "进行中"  // 计数任务的初始状态
    case completed = "已完成"
}

// 1. 【数据模型】定义您的提醒事项的结构
struct ReminderItem: Identifiable, Codable {
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

        // 如果是第一次运行，列表为空，则加载初始示例数据
        if reminders.isEmpty {
            loadInitialExampleReminders()
        }
    }

    // 🚀 【加载数据】从 UserDefaults 读取并解码
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
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            // 如果找到匹配的 ID，则更新现有项目
            reminders[index] = reminder
        } else {
            // 否则，添加新项目
            reminders.append(reminder)
        }
    }

    // 【删除】
    func delete(offsets: IndexSet) {
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
}

// 3. 【用户界面】主视图 ContentView
struct ContentView: View {
    // 声明数据管理器，@StateObject确保其生命周期与视图绑定
    @StateObject var manager = ReminderManager()
    @State private var isShowingAddView = false
    // 🚀 增加一个状态，用于存储正在被编辑的提醒事项
    @State private var editingReminder: ReminderItem?

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
                    manager.addExampleReminder()
                } label: {
                    Image(systemName: "plus.circle.fill")  // iOS 系统的加号图标
                }
            }
            .sheet(item: $editingReminder) { reminder in
                // 弹窗用于编辑现有项目 (item: $editingReminder)
                AddReminderView(reminder: reminder) { updatedReminder in
                    manager.addOrUpdate(reminder: updatedReminder)
                }
            }
            .sheet(isPresented: $isShowingAddView) {
                // 弹窗用于添加新项目 (isPresented: $isShowingAddView)
                // 传入一个空的/新的 ReminderItem
                AddReminderView(
                    reminder: ReminderItem(
                        name: "",
                        account: "",
                        description: "",
                        nextDueDate: Date(),
                        recurrence: "每年重复"
                    )
                ) { newReminder in
                    manager.addOrUpdate(reminder: newReminder)
                }
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

    // 用于保存用户在界面上的输入状态，从传入的 reminder 中初始化
    @State private var name: String
    @State private var account: String
    @State private var description: String
    @State private var dueDate: Date
    @State private var recurrence: String

    let recurrenceOptions = ["一次性任务", "每月初提醒", "每年重复", "自定义..."]

    // 🚀 初始化方法：将传入的 reminder 的值赋值给 @State 变量
    init(reminder: ReminderItem, onSave: @escaping (ReminderItem) -> Void) {
        self.onSave = onSave
        self._reminder = State(initialValue: reminder)

        self._name = State(initialValue: reminder.name)
        self._account = State(initialValue: reminder.account)
        self._description = State(initialValue: reminder.description)
        self._dueDate = State(initialValue: reminder.nextDueDate)
        self._recurrence = State(initialValue: reminder.recurrence)
    }

    var body: some View {
        NavigationView {
            Form {
                // ... (表单内容保持不变)
                Section(header: Text("核心信息")) {
                    TextField("提醒名称 (例如: 万豪房券)", text: $name)
                    TextField("关联账户 (例如: Marriott)", text: $account)
                }

                Section(header: Text("时间与频率")) {
                    DatePicker(
                        "下一个到期日",
                        selection: $dueDate,
                        displayedComponents: .date
                    )

                    Picker("重复频率", selection: $recurrence) {
                        ForEach(recurrenceOptions, id: \.self) { option in
                            Text(option)
                        }
                    }
                }

                Section(header: Text("详细描述")) {
                    TextEditor(text: $description)
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
                        // 1. 创建一个包含所有最新输入的 ReminderItem
                        let updatedReminder = ReminderItem(
                            id: reminder.id,  // 保持 ID 不变，这样 manager 知道要更新哪个
                            name: name,
                            account: account,
                            description: description,
                            nextDueDate: dueDate,
                            recurrence: recurrence
                        )
                        // 2. 调用回调函数，将数据传回主列表进行保存/更新
                        onSave(updatedReminder)
                        dismiss()
                    }
                    .disabled(name.isEmpty || account.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
