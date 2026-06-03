import AppKit

final class SegmentedQuotaMeterView: NSView {
    private var percent: Int = 0
    private var filledColor: NSColor = .systemRed
    private let segmentCount: Int
    private let verticalInset: CGFloat

    init(segmentCount: Int = 24, verticalInset: CGFloat = 3) {
        self.segmentCount = segmentCount
        self.verticalInset = verticalInset
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.segmentCount = 24
        self.verticalInset = 3
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 16)
    }

    func update(percent: Int, color: NSColor) {
        self.percent = max(0, min(100, percent))
        filledColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gap: CGFloat = 2
        let rect = bounds.insetBy(dx: 0, dy: verticalInset)
        let segmentWidth = max(2, (rect.width - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount))
        let filledSegments = Int((CGFloat(segmentCount) * CGFloat(percent) / 100).rounded(.toNearestOrAwayFromZero))

        for index in 0..<segmentCount {
            let x = rect.minX + CGFloat(index) * (segmentWidth + gap)
            let segmentRect = NSRect(x: x, y: rect.minY, width: segmentWidth, height: rect.height)
            let color = index < filledSegments
                ? filledColor
                : NSColor.controlColor.withAlphaComponent(0.35)
            color.setFill()
            NSBezierPath(roundedRect: segmentRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

final class QuotaBarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let meter = SegmentedQuotaMeterView()

    init() {
        super.init(frame: .zero)
        setup()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(with window: QuotaWindow?) {
        guard let window else {
            titleLabel.stringValue = "--"
            percentLabel.stringValue = "--%"
            resetLabel.stringValue = "暂无数据"
            meter.update(percent: 0, color: .systemRed)
            return
        }

        titleLabel.stringValue = window.title
        percentLabel.stringValue = "\(window.remainingPercent)%"
        resetLabel.stringValue = compactResetText(from: window)
        meter.update(percent: window.remainingPercent, color: quotaColor(for: window.remainingPercent))
    }

    private func setup() {
        wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right
        resetLabel.font = .systemFont(ofSize: 11, weight: .regular)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.alignment = .right

        [titleLabel, meter, percentLabel, resetLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: meter.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),

            meter.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            meter.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.widthAnchor.constraint(equalToConstant: 180),
            meter.heightAnchor.constraint(equalToConstant: 16),

            percentLabel.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 10),
            percentLabel.centerYAnchor.constraint(equalTo: meter.centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 42),

            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            resetLabel.leadingAnchor.constraint(equalTo: percentLabel.trailingAnchor, constant: 12),
            resetLabel.centerYAnchor.constraint(equalTo: meter.centerYAnchor),
            resetLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            meter.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            meter.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    private func compactResetText(from window: QuotaWindow) -> String {
        guard let resetsAt = window.resetsAt else {
            return "重置 --"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = resetDateFormat(for: window)
        return "重置 " + formatter.string(from: resetsAt)
    }

    private func resetDateFormat(for window: QuotaWindow) -> String {
        if let windowDurationMins = window.windowDurationMins, windowDurationMins >= 24 * 60 {
            return "M月d日"
        }

        return "HH:mm"
    }

    private func quotaColor(for remainingPercent: Int) -> NSColor {
        if remainingPercent <= 20 {
            return .systemRed
        }
        if remainingPercent <= 50 {
            return .systemYellow
        }
        return .systemGreen
    }
}

final class QuotaPanelView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Codex 额度")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let primaryView = QuotaBarView()
    private let secondaryView = QuotaBarView()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: QuotaSnapshot, error: String?) {
        titleLabel.stringValue = snapshot.limitName
        let plan = snapshot.planType.map { " · " + $0 } ?? ""
        subtitleLabel.stringValue = "本机 Codex app-server" + plan
        primaryView.update(with: snapshot.primary)
        secondaryView.update(with: snapshot.secondary)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        let time = "更新 " + formatter.string(from: snapshot.updatedAt)
        statusLabel.stringValue = error.map { time + " · " + $0 } ?? time
        statusLabel.textColor = error == nil ? .secondaryLabelColor : .systemRed
    }

    private func setup() {
        frame = NSRect(x: 0, y: 0, width: 410, height: 150)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [titleLabel, subtitleLabel, primaryView, secondaryView, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            primaryView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryView.heightAnchor.constraint(equalToConstant: 24),
            secondaryView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}

final class TouchBarQuotaView: NSView {
    private let primary = TouchBarQuotaRowView()
    private let secondary = TouchBarQuotaRowView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: QuotaSnapshot) {
        primary.update(with: snapshot.primary)
        secondary.update(with: snapshot.secondary)
    }

    private func setup() {
        frame = NSRect(x: 0, y: 0, width: 660, height: 30)
        wantsLayer = true
        appearance = NSAppearance(named: .vibrantDark)
        layer?.backgroundColor = NSColor.black.cgColor

        let stack = NSStackView(views: [primary, secondary])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            primary.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondary.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }
}

final class TouchBarQuotaRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let meter = SegmentedQuotaMeterView(segmentCount: 28, verticalInset: 2)
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(with window: QuotaWindow?) {
        guard let window else {
            titleLabel.stringValue = "--"
            percentLabel.stringValue = "--%"
            resetLabel.stringValue = "重置 --"
            meter.update(percent: 0, color: .systemRed)
            return
        }

        titleLabel.stringValue = window.title
        percentLabel.stringValue = "\(window.remainingPercent)%"
        resetLabel.stringValue = compactResetText(from: window)
        meter.update(percent: window.remainingPercent, color: quotaColor(for: window.remainingPercent))
    }

    private func setup() {
        wantsLayer = true
        [titleLabel, percentLabel, resetLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            $0.textColor = .white
            $0.alignment = .right
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        titleLabel.alignment = .left
        resetLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        resetLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        meter.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, meter, percentLabel, resetLabel].forEach(addSubview)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 15),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 40),

            meter.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            meter.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.heightAnchor.constraint(equalToConstant: 12),
            meter.widthAnchor.constraint(equalToConstant: 230),

            percentLabel.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 8),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 34),

            resetLabel.leadingAnchor.constraint(equalTo: percentLabel.trailingAnchor, constant: 8),
            resetLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resetLabel.widthAnchor.constraint(equalToConstant: 66),
            resetLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    private func compactResetText(from window: QuotaWindow) -> String {
        guard let resetsAt = window.resetsAt else {
            return "重置 --"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = resetDateFormat(for: window)
        return "重置 " + formatter.string(from: resetsAt)
    }

    private func resetDateFormat(for window: QuotaWindow) -> String {
        if let windowDurationMins = window.windowDurationMins, windowDurationMins >= 24 * 60 {
            return "M月d日"
        }

        return "HH:mm"
    }

    private func quotaColor(for remainingPercent: Int) -> NSColor {
        if remainingPercent <= 20 {
            return .systemRed
        }
        if remainingPercent <= 50 {
            return .systemYellow
        }
        return .systemGreen
    }
}
