import UIKit

public final class SparkNetLogerSettingsViewController: UIViewController {
    private let toggle = UISwitch()
    private let statusLabel = UILabel()
    private let addressLabel = UILabel()
    private let countLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private var observation: SparkNetLogerObservation?

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("title"); view.backgroundColor = .systemGroupedBackground
        let titleLabel = UILabel(); titleLabel.text = L10n.text("heading"); titleLabel.numberOfLines = 0; titleLabel.font = .preferredFont(forTextStyle: .headline)
        let row = UIStackView(arrangedSubviews: [titleLabel, toggle]); row.axis = .horizontal
        let note = UILabel(); note.text = L10n.text("note")
        note.numberOfLines = 0; note.textColor = .secondaryLabel
        addressLabel.numberOfLines = 0; addressLabel.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        statusLabel.numberOfLines = 0
        copyButton.setTitle(L10n.text("copyAddress"), for: .normal)
        copyButton.addTarget(self, action: #selector(copyAddress), for: .touchUpInside)
        toggle.addTarget(self, action: #selector(change), for: .valueChanged)
        toggle.accessibilityIdentifier = "liveLoggingSwitch"
        addressLabel.accessibilityIdentifier = "webAddress"
        let stack = UIStackView(arrangedSubviews: [row, statusLabel, addressLabel, copyButton, countLabel, note])
        stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView(); scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView); scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        observation = SparkNetLoger.observeState { [weak self] state in self?.render(state) }
    }
    private func render(_ state: SparkNetLogerState) {
        toggle.isOn = state.liveLoggingRequested; toggle.isEnabled = state.enabled
        let labels: [SparkNetLogerState.Phase: String] = [
            .disabled: L10n.text("disabled"), .off: L10n.text("off"), .waitingForWiFi: L10n.text("waiting"),
            .starting: L10n.text("starting"), .running: L10n.text("running"), .paused: L10n.text("paused"), .failed: L10n.text("failed")
        ]
        statusLabel.text = labels[state.phase]! + (state.errorMessage.map { "\n" + $0 } ?? "")
            + (state.noticeMessage.map { "\n" + $0 } ?? "")
        addressLabel.text = state.webURL?.absoluteString ?? L10n.text("addressPending")
        copyButton.isEnabled = state.webURL != nil
        countLabel.text = L10n.text("connections", state.connectionCount)
    }
    @objc private func change() {
        if toggle.isOn { SparkNetLoger.startLiveLogging() } else { SparkNetLoger.stopLiveLogging() }
    }
    @objc private func copyAddress() { UIPasteboard.general.string = SparkNetLoger.state.webURL?.absoluteString }
}
