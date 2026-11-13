import UIKit

/// The list screen: the playlist sheet (URL, Load, status) and under it the channels, one 57-point row each, in the
/// page's column (inside the left and right safe area, as WebKit lays the page out). The table is the page: it is
/// the only thing that scrolls.
final class ListScreen: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let header = PlaylistSheet()
    private var names: [String] = []
    private var channels: [Channel] = []
    private var run = 0

    override func loadView() {
        view = UIView()
        view.backgroundColor = .ground
        table.backgroundColor = .ground
        table.separatorStyle = .none
        table.rowHeight = 57
        table.estimatedRowHeight = 57
        table.sectionHeaderTopPadding = 0
        table.showsVerticalScrollIndicator = false
        table.keyboardDismissMode = .onDrag
        table.dataSource = self
        table.delegate = self
        table.register(ChannelCell.self, forCellReuseIdentifier: "ch")
        view.addSubview(table)
        header.field.delegate = self
        header.button.onTap = { [weak self] in self?.load() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let forced = Forced.list {
            header.field.text = forced.url
            header.set(forced.text, bad: forced.bad)
            names = forced.channels
            return
        }
        header.field.text = Store.address
        channels = Store.cached()
        names = channels.map(\.name)
        header.set(channels.isEmpty ? Words.none : Words.count(channels.count), bad: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let frame = CGRect(x: safe.left, y: 0, width: view.bounds.width - safe.left - safe.right, height: view.bounds.height)
        if table.frame != frame { table.frame = frame }
        if header.frame.width != frame.width {
            header.frame = CGRect(x: 0, y: 0, width: frame.width, height: PlaylistSheet.height + (names.isEmpty ? 0 : 8))
            header.layout()
            table.tableHeaderView = header
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }

    /// The sheet's height follows whether channels sit under it (the 8-point gap belongs to the channels' sheet).
    private func resizeHeader() {
        header.frame.size.height = PlaylistSheet.height + (names.isEmpty ? 0 : 8)
        table.tableHeaderView = header
    }

    // ---- loading ----

    private func load() {
        guard Forced.list == nil else { return }
        header.field.resignFirstResponder()
        run += 1
        let mine = run
        header.set(Words.loading, bad: false)
        Store.load(header.field.text ?? "") { [weak self] result in
            guard let self, mine == self.run else { return }
            switch result {
            case .success(let list):
                self.channels = list
                self.names = list.map(\.name)
                self.header.set(Words.count(list.count), bad: false)
                self.resizeHeader()
                self.table.reloadData()
            case .failure(let why):
                // the channels already shown stay: they still play
                self.header.set(why == .empty ? Words.noChannels : why == .notAddress ? Words.notAddress : Words.failed, bad: true)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        load()
        return false
    }

    // ---- the channels ----

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { names.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ch", for: indexPath) as! ChannelCell
        cell.name.text = names[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < channels.count else { return }   // a held state has names only
        header.field.resignFirstResponder()
        let player = PlayerScreen(channels[indexPath.row])
        player.modalPresentationStyle = .fullScreen
        present(player, animated: false)
    }
}

/// The playlist sheet: label, the URL field joined to its Load button, and the status line.
final class PlaylistSheet: UIView {
    static let height: CGFloat = 132   // 16 + 20 label + 8 + 44 field + 8 + 20 status + 16
    private let sheet = Box(.panel)
    private let label = Label(Words.label, size: 13, color: .muted, lineHeight: 20)
    let field = URLField()
    private let edges = [Box(.rule), Box(.rule), Box(.rule)]   // the field's top, left and bottom border
    let button = Block(Words.load, fill: .ink, textColor: .panel)
    private let cross = IconView(Icon.cross, size: 16)
    private let status = Label(Words.none, size: 13, color: .muted, lineHeight: 20)
    private var bad = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .ground
        sheet.isUserInteractionEnabled = false
        for v in ([sheet, label, field, button, cross, status] as [UIView]) + (edges as [UIView]) { addSubview(v) }
        cross.isHidden = true
        status.accessibilityIdentifier = "status"
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, bad: Bool) {
        self.bad = bad
        status.text = text
        status.color = bad ? .ink : .muted
        cross.isHidden = !bad
        layout()
    }

    // the table sets the header's width itself (a rotation, a new header height): lay out whenever the size changes
    override func layoutSubviews() {
        super.layoutSubviews()
        layout()
    }

    func layout() {
        let w = bounds.width
        sheet.frame = CGRect(x: 0, y: 0, width: w, height: PlaylistSheet.height)
        label.frame = CGRect(x: 16, y: 16, width: w - 32, height: 20)
        let bw = button.naturalWidth
        let fieldFrame = CGRect(x: 16, y: 44, width: w - 32 - bw, height: 44)
        field.frame = fieldFrame
        button.frame = CGRect(x: fieldFrame.maxX, y: 44, width: bw, height: 44)
        edges[0].frame = CGRect(x: 16, y: 44, width: fieldFrame.width, height: 1)
        edges[1].frame = CGRect(x: 16, y: 44, width: 1, height: 44)
        edges[2].frame = CGRect(x: 16, y: 87, width: fieldFrame.width, height: 1)
        cross.frame = CGRect(x: 16, y: 98, width: 16, height: 16)
        status.frame = CGRect(x: bad ? 38 : 16, y: 96, width: w - 32 - (bad ? 22 : 0), height: 20)
    }
}

/// The page's `input`: 15-point text, 12 of padding inside a 1-point border.
final class URLField: UITextField {
    init() {
        super.init(frame: .zero)
        font = Fonts.ui(15, 400)
        textColor = .ink
        tintColor = .ink
        backgroundColor = .panel
        borderStyle = .none
        keyboardType = .URL
        textContentType = .URL
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        returnKeyType = .go
        clearButtonMode = .never
        accessibilityLabel = Words.label
        attributedPlaceholder = NSAttributedString(string: Words.placeholder, attributes: [.foregroundColor: UIColor.muted, .font: Fonts.ui(15, 400)])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func inner(_ b: CGRect) -> CGRect { b.inset(by: UIEdgeInsets(top: 1, left: 13, bottom: 1, right: 12)) }
    override func textRect(forBounds bounds: CGRect) -> CGRect { inner(bounds) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { inner(bounds) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { inner(bounds) }
}

/// One channel: its name in a 28-point line 14 below the row's top, and the rule along the row's bottom edge.
final class ChannelCell: UITableViewCell {
    let name = Label("", size: 18, weight: 500, lineHeight: 28)
    private let rule = Box(.rule)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .panel
        contentView.backgroundColor = .panel
        contentView.addSubview(name)
        contentView.addSubview(rule)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        name.frame = CGRect(x: 16, y: 14, width: bounds.width - 32, height: 28)
        rule.frame = CGRect(x: 0, y: 56, width: bounds.width, height: 1)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: false)
        contentView.backgroundColor = highlighted ? .ground : .panel
    }
}
