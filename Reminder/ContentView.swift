import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

// 定义任务状态（保持不变）
enum ReminderStatus: String, Codable {
    case pending = "待完成"
    case inProgress = "进行中"
    case completed = "已完成"
}

struct ReminderItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var account: String
    var description: String

    // 【任务核心】任务到期/重置的截止日期
    var nextDueDate: Date
    var recurrence: String  // 任务的年度周期 (例如: "每年重复")

    // 【提醒核心】下一次提醒的具体时间（新增）
    var nextNotificationDate: Date  // 下一次通知的具体日期和时间
    var notificationRecurrence: String  // 通知频率 (例如: "每月提醒", "每周提醒")

    var status: ReminderStatus
    var targetCount: Int
    var currentCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        account: String,
        description: String,
        nextDueDate: Date,
        recurrence: String,
        // 🚀 新增：默认的下一次提醒日期设置为到期日
        nextNotificationDate: Date = Date(),
        notificationRecurrence: String = "每月提醒",
        targetCount: Int = 1,
        currentCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.account = account
        self.description = description
        self.nextDueDate = nextDueDate
        self.recurrence = recurrence
        self.nextNotificationDate = nextNotificationDate  // 使用新增字段
        self.notificationRecurrence = notificationRecurrence
        self.targetCount = targetCount
        self.currentCount = currentCount

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

    // ⚠️ 原始的 scheduleNotification 现在用作总入口
    func scheduleNotification(for reminder: ReminderItem) {
        // 先清理所有旧通知，防止冲突
        cancelNotification(for: reminder)

        // 只有当任务处于未完成状态时，才设置周期性提醒
        if reminder.status != .completed {
            schedulePeriodicNotification(for: reminder)
        }

        // 如果任务是重复的 (例如: 每年重置)，则设置一个“重置触发器”
        if reminder.recurrence == "每年重复" || reminder.recurrence == "每月初提醒" {
            scheduleResetTrigger(for: reminder)
        }
    }

    // 🚀 辅助方法 1: 设置周期性提醒通知 (使用 nextNotificationDate 作为起始点)
    private func schedulePeriodicNotification(for reminder: ReminderItem) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "⏰ 待办提醒：\(reminder.name)"
        content.body =
            "账户：\(reminder.account)。请在到期日 \(reminder.nextDueDate.formatted(date: .abbreviated, time: .omitted)) 前完成。"
        content.sound = UNNotificationSound.default

        var trigger: UNCalendarNotificationTrigger?
        var repeats = true

        // 默认以用户设定的 nextNotificationDate 作为单次提醒
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .weekday],
            from: reminder.nextNotificationDate
        )

        // 如果是周期性提醒，则忽略 nextNotificationDate 的日期，只取时间，并设置重复规则
        switch reminder.notificationRecurrence {
        case "每周提醒":
            // 设置每周在用户指定的 nextNotificationDate 的“周几”和“时间”重复
            components.weekday = Calendar.current.component(
                .weekday,
                from: reminder.nextNotificationDate
            )
            components.year = nil
            components.month = nil
            components.day = nil
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )

        case "每月提醒":
            // 设置每月在用户指定的 nextNotificationDate 的“几号”和“时间”重复
            components.day = Calendar.current.component(
                .day,
                from: reminder.nextNotificationDate
            )
            components.year = nil
            components.month = nil
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )

        case "无提醒":
            // 仅设置一次，日期和时间都取 nextNotificationDate 的值
            repeats = false
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

        default:
            return
        }

        guard let finalTrigger = trigger else { return }

        let periodicID = "\(reminder.id.uuidString)_PERIODIC"
        let request = UNNotificationRequest(
            identifier: periodicID,
            content: content,
            trigger: finalTrigger
        )

        center.add(request) { error in
            if let error = error {
                print("设置周期性通知失败: \(error.localizedDescription)")
            } else {
                print(
                    "周期性通知 (\(reminder.notificationRecurrence)) 已安排，ID: \(periodicID)"
                )
            }
        }
    }

    // 🚀 任务自动重置/复活 (`resetTask`)
    func resetTask(taskID: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == taskID })
        else { return }

        guard reminders[index].status == .completed else { return }

        let originalItem = reminders[index]

        // 1. 计算下一个任务重置日 (nextDueDate)
        var components = DateComponents()
        if originalItem.recurrence == "每年重复" {
            components.year = 1
        } else if originalItem.recurrence == "每月初提醒" {
            components.month = 1
        } else {
            return
        }

        if let newNextDueDate = Calendar.current.date(
            byAdding: components,
            to: originalItem.nextDueDate
        ) {
            reminders[index].nextDueDate = newNextDueDate
        }

        // 2. 🚀 关键修改：重置 nextNotificationDate
        // 将下一次提醒日设置为“今天”或“下一个到期日”之后的某个时间点。
        // 为了简化，我们将其重置为当前的日期和时间。
        reminders[index].nextNotificationDate = Date()

        // 3. 重置状态和计数
        reminders[index].currentCount = 0
        reminders[index].status =
            reminders[index].targetCount > 1 ? .inProgress : .pending

        // 4. 重新安排通知
        scheduleNotification(for: reminders[index])

        print(
            "任务 '\(originalItem.name)' 已在 \(Date().formatted()) 自动重置并安排了新的周期提醒。"
        )
    }

    // 🚀 辅助方法 2: 设置任务重置触发器 (例如：明年的 9 月 25 日)
    private func scheduleResetTrigger(for reminder: ReminderItem) {
        let center = UNUserNotificationCenter.current()

        // 1. 计算下一个重置日期（基于 nextDueDate 和 recurrence 字段）
        var components = DateComponents()
        if reminder.recurrence == "每年重复" {
            components.year = 1
        } else if reminder.recurrence == "每月初提醒" {
            components.month = 1
        } else {
            return  // 如果不是重复任务，则不需要重置触发器
        }

        guard
            let nextResetDate = Calendar.current.date(
                byAdding: components,
                to: reminder.nextDueDate
            )
        else { return }

        // 2. 将实际的重置日期存储到 UserInfo 中，以便在通知触发时识别是哪个任务需要重置
        let content = UNMutableNotificationContent()
        content.title = "✅ 任务重置触发器：\(reminder.name)"
        content.body = "这是一个内部触发器，用于重置任务。重置日：\(nextResetDate.formatted())"
        content.sound = nil  // 内部触发器，不发声
        content.userInfo = [
            "taskID": reminder.id.uuidString, "action": "reset",
        ]

        let resetDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: nextResetDate
        )
        // 每天早上 8 点触发重置逻辑
        var finalResetComponents = resetDateComponents
        finalResetComponents.hour = 8
        finalResetComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: finalResetComponents,
            repeats: false
        )

        // ⚠️ 使用一个带有 "RESET" 后缀的 ID
        let resetID = "\(reminder.id.uuidString)_RESET"
        let request = UNNotificationRequest(
            identifier: resetID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("设置重置触发器失败: \(error.localizedDescription)")
            } else {
                print("重置触发器已安排 (\(nextResetDate.formatted()))，ID: \(resetID)")
            }
        }
    }

    // ⚠️ 额外的通知清理：在编辑、删除或完成时调用
    func cancelNotification(for reminder: ReminderItem) {
        // 清理周期性提醒和重置触发器
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "\(reminder.id.uuidString)_PERIODIC",
                "\(reminder.id.uuidString)_RESET",
                reminder.id.uuidString,  // 原始的单次通知 ID
            ]
        )
        print("已取消与任务 \(reminder.id.uuidString) 相关的所有通知。")
    }

    // 🚀 关键修改：完成任务时，停止周期提醒，并设置下一个年度重置
    func completeTask(item: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id })
        else { return }

        // 1. 取消所有周期性通知（停止骚扰用户）
        cancelNotification(for: item)

        // 2. 标记任务为完成状态
        reminders[index].status = .completed
        reminders[index].currentCount = reminders[index].targetCount

        // 3. 保持“重置触发器”不变！
        // 因为我们在 scheduleNotification 中已经设置了年度重置触发器（ID: XXX_RESET）。
        // 当任务完成时，我们只取消了周期性提醒（ID: XXX_PERIODIC），
        // 这样到了下一个年度重置日，RESET 触发器仍然会启动，并调用 resetTask。
        print("任务 '\(item.name)' 已完成。年度重置触发器保持不变，等待明年重置。")
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
// 3. 【用户界面】主视图 ContentView
struct ContentView: View {
    // ⚠️ 更改为 @ObservedObject 或直接 var，表示它是从外部传入的
    @ObservedObject var manager: ReminderManager  // <--- 关键修改

    @State private var isShowingAddView = false
    // 🚀 增加一个状态，用于存储正在被编辑的提醒事项
    @State private var editingReminder: ReminderItem?
    // 🚀 新增状态：控制视图显示“未完成”还是“已完成”
    @State private var selectedStatus: ReminderStatus = .pending  // .pending 用于代表“未完成”和“进行中”的任务

    // 🚀 计算属性：根据当前选择的状态过滤出要显示的列表
    var filteredReminders: [ReminderItem] {
        if selectedStatus == .completed {
            return manager.reminders.filter { $0.status == .completed }
        } else {
            // “待完成”(.pending) 和 “进行中”(.inProgress) 视为同一类：未完成
            return manager.reminders.filter { $0.status != .completed }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                // 1. 添加状态切换器 (Segmented Picker)
                Picker("任务状态", selection: $selectedStatus) {
                    Text(
                        "待处理 (\(manager.reminders.filter { $0.status != .completed }.count))"
                    ).tag(ReminderStatus.pending)
                    Text(
                        "已完成 (\(manager.reminders.filter { $0.status == .completed }.count))"
                    ).tag(ReminderStatus.completed)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])  // 增加一些边距

                // List 用于展示可滚动的列表数据
                List {
                    // 2. 遍历过滤后的列表
                    ForEach(filteredReminders) { item in
                        // 3. 使用您创建的 ReminderRow 视图
                        ReminderRow(
                            item: item,
                            manager: manager,
                            editingReminder: $editingReminder
                        )
                    }
                    // 4. 更新 .onDelete 逻辑以确保在过滤列表上的删除是安全的
                    .onDelete { offsets in
                        // 1. 找到要删除项目在 filteredReminders 中的 ID
                        let remindersToDelete = offsets.map {
                            filteredReminders[$0]
                        }

                        // 2. 将这些 ID 映射回 manager.reminders 列表中的原始索引
                        let indicesToDelete = IndexSet(
                            remindersToDelete.compactMap { reminder in
                                manager.reminders.firstIndex(where: {
                                    $0.id == reminder.id
                                })
                            }
                        )

                        // 3. 使用原始索引集进行删除
                        manager.delete(offsets: indicesToDelete)
                    }
                }
            }  // end VStack

            // 列表的导航栏标题
            .navigationTitle("账户提醒事项")

            // 导航栏右上角的按钮
            .toolbar {
                // ... (ToolbarItem 保持不变)
                Button {
                    isShowingAddView = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .sheet(item: $editingReminder) { reminder in
                // 弹窗用于编辑现有项目
                AddReminderView(
                    onSave: { updatedReminder in
                        manager.addOrUpdate(reminder: updatedReminder)
                    },
                    reminder: reminder
                )
            }
            .sheet(isPresented: $isShowingAddView) {
                // 弹窗用于添加新项目
                AddReminderView(
                    onSave: { newReminder in
                        manager.addOrUpdate(reminder: newReminder)
                    },
                    reminder: ReminderItem(
                        name: "",
                        account: "",
                        description: "",
                        nextDueDate: Date(),
                        recurrence: "每年重复",
                        targetCount: 1,
                        currentCount: 0
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
    let notificationRecurrenceOptions = ["无提醒", "每周提醒", "每月提醒"]

    var body: some View {
        NavigationView {
            Form {
                // ... (表单内容保持不变)
                Section(header: Text("核心信息")) {
                    TextField("提醒名称 (例如: 万豪房券)", text: $reminder.name)
                    TextField("关联账户 (例如: Marriott)", text: $reminder.account)
                }
                // --- 目标和频率 ---
                Section(header: Text("任务重置与目标")) {
                    // 🚀 新增：目标计数输入，绑定到 $reminder.targetCount
                    // 计数范围从 1 次到 20 次，如果任务是计数型，targetCount > 1
                    Stepper(
                        "目标次数: \(reminder.targetCount)",
                        value: $reminder.targetCount,
                        in: 1...20
                    )

                    // 任务重复周期 (决定何时重置)
                    Picker("重置周期", selection: $reminder.recurrence) {
                        ForEach(recurrenceOptions, id: \.self) { Text($0) }
                    }

                    // 任务到期/重置日 (决定何时触发年度重置)
                    DatePicker(
                        "任务到期/重置日",
                        selection: $reminder.nextDueDate,
                        displayedComponents: .date
                    )

                    // 🚀 新增：通知提醒频率 (决定提醒用户的频率)
                    Picker(
                        "通知提醒频率",
                        selection: $reminder.notificationRecurrence
                    ) {
                        ForEach(notificationRecurrenceOptions, id: \.self) {
                            option in
                            Text(option)
                        }
                    }
                }
                Section(header: Text("通知提醒设置")) {
                    // 通知提醒频率
                    Picker(
                        "提醒频率",
                        selection: $reminder.notificationRecurrence
                    ) {
                        ForEach(notificationRecurrenceOptions, id: \.self) {
                            option in
                            Text(option)
                        }
                    }

                    // 🚀 新增：下一次提醒的具体日期和时间
                    DatePicker(
                        "下一次提醒日",
                        selection: $reminder.nextNotificationDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section(header: Text("详细描述")) {
                    TextEditor(text: $reminder.description)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(reminder.name.isEmpty ? "添加新任务" : "任务")  // 根据名称判断标题
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

// 新视图：单个提醒事项的行
// 新视图：单个提醒事项的行（已修复数据流问题）
struct ReminderRow: View {
    // ⚠️ 关键修复：将 @State var item 更改为 let item
    // 接收来自 ContentView 传递的最新值，不再持有本地副本。
    let item: ReminderItem

    @ObservedObject var manager: ReminderManager  // 访问管理器方法
    @Binding var editingReminder: ReminderItem?  // 用于编辑弹窗

    // 【注意：现在 body 内部的 item 变量，总是 manager.reminders 数组中的最新数据】
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {

                // 任务名称和账户信息
                Text(item.name)
                    .font(.headline)
                    // 🚀 如果已完成，显示横线
                    .strikethrough(item.status == .completed)

                HStack {
                    Text("账户: \(item.account)").font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(item.recurrence).font(.caption).foregroundColor(
                        .secondary
                    )
                }

                // 计数进度或截止日期
                if item.targetCount > 1 {
                    // 计数任务显示进度
                    Text("进度: \(item.currentCount) / \(item.targetCount)").font(
                        .caption
                    ).foregroundColor(.blue)
                } else {
                    // 一次性任务显示日期
                    Text(
                        "到期日: \(item.nextDueDate.formatted(date: .abbreviated, time: .omitted))"
                    ).font(.caption).foregroundColor(.orange)
                }

                // 任务状态
                Text(item.description).font(.caption).lineLimit(1)
            }
            .onTapGesture {
                // 点击行时触发编辑
                editingReminder = item  // item 是最新的，没问题
            }

            Spacer()

            // 🚀 快捷操作按钮
            VStack {
                if item.status != .completed {
                    // 未完成/进行中状态下
                    if item.targetCount > 1 {
                        // 计数任务：显示 +1 按钮
                        Button("+1") {
                            // 调用 Manager 方法更新数据
                            manager.incrementCount(item: item)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        // 一次性任务：显示“完成”按钮
                        Button("完成") {
                            manager.completeTask(item: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    // 已完成状态：显示一个圆圈图标
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// 1. 创建一个类来处理通知中心的代理回调
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    // ⚠️ 存储 ReminderManager 的引用，以便在收到通知时调用它的方法
    var manager: ReminderManager?

    // 【关键方法】：当 App 收到通知时，无论 App 是在前台、后台还是被唤醒，都会调用此方法
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 1. 提取通知的内容和用户信息
        let userInfo = response.notification.request.content.userInfo

        // 2. 检查这是否是我们的任务重置触发器
        if userInfo["action"] as? String == "reset",
            let taskIDString = userInfo["taskID"] as? String,
            let taskID = UUID(uuidString: taskIDString)
        {
            print("代理：收到任务重置通知！ID: \(taskIDString)")

            // 3. 调用 ReminderManager 的方法执行重置逻辑
            // ⚠️ 确保 manager 实例已经设置
            manager?.resetTask(taskID: taskID)
        }

        // 4. 必须调用 completionHandler，告诉系统您已处理完毕
        completionHandler()
    }

    // 可选：当 App 处于前台时收到通知，会调用此方法
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 在前台收到通知时，不展示给用户 (因为它是不发声的内部触发器)
        if notification.request.content.userInfo["action"] as? String == "reset"
        {
            completionHandler([])  // 不展示横幅、声音等
        } else {
            completionHandler([.banner, .sound, .badge])  // 其他通知正常显示
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
    ContentView(manager: ReminderManager())
}
