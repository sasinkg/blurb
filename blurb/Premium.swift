import CryptoKit
import FirebaseAuth
import FirebaseFunctions
import StoreKit
import SwiftUI
import UIKit

@MainActor
final class GroupPremiumManager: ObservableObject {
    static let productID = "sasinkg.blurb.group.premium.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    init() {
        Task { await loadProduct() }
    }

    func loadProduct() async {
        errorMessage = nil
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                errorMessage = "Blurb Premium is not available from the App Store yet."
            }
        } catch {
            errorMessage = "Premium pricing is unavailable right now."
        }
    }

    func totalPriceLabel() -> String {
        product?.displayPrice ?? "App Store price"
    }

    func perPersonLabel(memberCount: Int) -> String {
        let count = max(memberCount, 1)
        guard let product else {
            return "Per-person estimate appears when App Store pricing loads"
        }
        let price = product.price
        let perPerson = price / Decimal(count)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = product.priceFormatStyle.currencyCode
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: perPerson as NSDecimalNumber) ?? "$\(perPerson)"
        return "About \(value) per person with \(count) \(count == 1 ? "member" : "members")"
    }

    func purchase(for group: BlurbGroup) async -> Bool {
        errorMessage = nil
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            errorMessage = "Premium is not available yet. Confirm the subscription is active in App Store Connect."
            return false
        }
        guard let userID = Auth.auth().currentUser?.uid else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(Self.accountToken(for: userID))])
            switch result {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                try await activate(signedTransaction: verification.jwsRepresentation, groupID: group.id)
                await transaction.finish()
                return true
            case .pending:
                errorMessage = "The purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func restore(for group: BlurbGroup) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            for await result in StoreKit.Transaction.currentEntitlements {
                let transaction = try Self.verified(result)
                guard transaction.productID == Self.productID else { continue }
                try await activate(signedTransaction: result.jwsRepresentation, groupID: group.id)
                return true
            }
            errorMessage = "No active Blurb Premium subscription was found."
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func activate(signedTransaction: String, groupID: String) async throws {
        _ = try await Functions.functions().httpsCallable("activateGroupPremium").call([
            "groupID": groupID,
            "signedTransaction": signedTransaction
        ])
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw PremiumError.failedVerification
        }
    }

    private static func accountToken(for userID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(userID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private enum PremiumError: LocalizedError {
        case failedVerification
        var errorDescription: String? { "The App Store purchase could not be verified." }
    }
}

extension GroupTheme {
    var color: Color {
        switch self {
        case .gold: Color(red: 1, green: 0.78, blue: 0.02)
        case .coral: Color(red: 0.98, green: 0.39, blue: 0.28)
        case .rose: Color(red: 0.92, green: 0.28, blue: 0.48)
        case .forest: Color(red: 0.12, green: 0.55, blue: 0.33)
        case .cobalt: Color(red: 0.18, green: 0.42, blue: 0.92)
        case .plum: Color(red: 0.56, green: 0.29, blue: 0.72)
        }
    }
}

extension BlurbGroup {
    var themeColor: Color {
        GroupTheme(rawValue: themeID)?.color ?? GroupTheme.gold.color
    }
}

struct GroupPremiumHubView: View {
    @EnvironmentObject private var premium: GroupPremiumManager
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var showingError = false

    private var currentGroup: BlurbGroup {
        blurbStore.groups.first(where: { $0.id == group.id }) ?? group
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: currentGroup.isPremium ? "crown.fill" : "sparkles")
                        .font(.system(size: 42))
                        .foregroundStyle(GroupTheme(rawValue: currentGroup.themeID)?.color ?? GroupTheme.gold.color)
                    Text(currentGroup.isPremium ? "Premium is active" : "Blurb Premium")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    Text("One subscription unlocks Premium for everyone in \(currentGroup.name).")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if !currentGroup.isPremium {
                    VStack(spacing: 5) {
                        Text("\(premium.totalPriceLabel()) / month for the whole group")
                            .font(.title3.bold())
                        Text(premium.perPersonLabel(memberCount: currentGroup.memberCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                premiumFeatureLinks

                if !currentGroup.isPremium {
                    Button {
                        Task {
                            if !(await premium.purchase(for: currentGroup)), premium.errorMessage != nil { showingError = true }
                        }
                    } label: {
                        Group {
                            if premium.isLoading { ProgressView().tint(.black) }
                            else { Text("Start group Premium") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(currentGroup.themeColor)
                    .foregroundStyle(.black)
                    .disabled(premium.isLoading)

                    Button("Restore purchase") {
                        Task {
                            if !(await premium.restore(for: currentGroup)), premium.errorMessage != nil { showingError = true }
                        }
                    }
                    .disabled(premium.isLoading)

                    Text("Subscription renews monthly until canceled. A restored subscription stays attached to its original group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 18) {
                        Link("Privacy Policy", destination: URL(string: "https://blurb-2296b.web.app/privacy")!)
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle("Group Premium")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Blurb Premium", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: { Text(premium.errorMessage ?? "Please try again.") }
    }

    private var premiumFeatureLinks: some View {
        VStack(spacing: 0) {
            featureLink("Group themes", icon: "paintpalette.fill") { GroupThemePickerView(group: currentGroup) }
            Divider()
            featureLink("Group Lore", icon: "bookmark.fill") { GroupLoreView(group: currentGroup) }
            Divider()
            featureLink("Time Capsules", icon: "hourglass") { TimeCapsulesView(group: currentGroup) }
            Divider()
            featureLink("Blurb archive", icon: "clock.arrow.circlepath") { GroupArchiveView(group: currentGroup) }
            Divider()
            featureLink(
                "Newsletter PDFs",
                subtitle: "Export from any saved newsletter",
                icon: "doc.richtext.fill"
            ) {
                GroupNewsletterHomeView(group: currentGroup)
            }
        }
        .padding(.horizontal, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func featureLink<Destination: View>(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                lock
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!currentGroup.isPremium)
        .accessibilityHint(currentGroup.isPremium ? "Opens \(title)" : "Requires group Premium")
    }

    @ViewBuilder private var lock: some View {
        if !currentGroup.isPremium { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
    }
}

struct GroupThemePickerView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup

    private var currentGroup: BlurbGroup {
        blurbStore.groups.first(where: { $0.id == group.id }) ?? group
    }

    var body: some View {
        List(GroupTheme.allCases) { theme in
            Button {
                Task { await blurbStore.setTheme(theme, for: group.id) }
            } label: {
                HStack {
                    Circle().fill(theme.color).frame(width: 30, height: 30)
                    Text(theme.name)
                    Spacer()
                    if currentGroup.themeID == theme.rawValue { Image(systemName: "checkmark") }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Group theme")
    }
}

struct GroupLoreView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup

    var body: some View {
        Group {
            if blurbStore.loreItems.isEmpty {
                ContentUnavailableView("Your lore starts here", systemImage: "bookmark", description: Text("Use the bookmark on a favorite answer to save it for the group."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(blurbStore.loreItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.prompt.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(item.answer).font(.body)
                                HStack { Text(item.authorName).font(.caption.bold()); Spacer(); Text(item.createdAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("\(group.name) Lore")
    }
}

struct TimeCapsulesView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var showingComposer = false
    @State private var openedContent: String?
    @State private var openedTitle = ""

    var body: some View {
        List {
            if blurbStore.timeCapsules.isEmpty {
                ContentUnavailableView("No capsules yet", systemImage: "hourglass", description: Text("Seal an answer, question, or prediction for your group to open later."))
                    .listRowBackground(Color.clear)
            }
            ForEach(blurbStore.timeCapsules) { capsule in
                Button {
                    guard capsule.isUnlocked else { return }
                    Task {
                        if let content = await blurbStore.openTimeCapsule(capsule) {
                            openedTitle = capsule.title
                            openedContent = content
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: capsule.isUnlocked ? "lock.open.fill" : "lock.fill")
                        VStack(alignment: .leading) {
                            Text(capsule.title).font(.headline)
                            Text(capsule.isUnlocked ? "Ready to open" : "Unlocks \(capsule.unlockAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Time Capsules")
        .toolbar { Button { showingComposer = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingComposer) { TimeCapsuleComposer(group: group) }
        .alert(openedTitle, isPresented: Binding(get: { openedContent != nil }, set: { if !$0 { openedContent = nil } })) {
            Button("Close", role: .cancel) { openedContent = nil }
        } message: { Text(openedContent ?? "") }
    }
}

private struct TimeCapsuleComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var kind = "prediction"
    @State private var title = ""
    @State private var content = ""
    @State private var unlockAt = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Prediction").tag("prediction")
                    Text("Question").tag("question")
                    Text("Answer").tag("answer")
                }
                TextField("Capsule title", text: $title)
                TextField("What should be sealed?", text: $content, axis: .vertical).lineLimit(4...10)
                DatePicker("Unlock date", selection: $unlockAt, in: Date.now..., displayedComponents: .date)
            }
            .navigationTitle("New capsule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") {
                        saving = true
                        Task {
                            if await blurbStore.createTimeCapsule(kind: kind, title: title, content: content, unlockAt: unlockAt, in: group.id) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GroupArchiveView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup

    private var archived: [BlurbPost] {
        blurbStore.posts.filter { $0.groupID == group.id }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List(archived) { post in
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(post.authorName).font(.headline); Spacer(); Text(post.createdAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                Text(post.prompt).font(.caption).foregroundStyle(.secondary)
                Text(post.answer)
            }
            .padding(.vertical, 5)
        }
        .overlay { if archived.isEmpty { ContentUnavailableView("No archived Blurbs", systemImage: "archivebox") } }
        .navigationTitle("Blurb archive")
    }
}

enum NewsletterPDFExporter {
    static func makePDF(for edition: NewsletterEdition) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(edition.groupName)-\(edition.monthKey).pdf")
        var images: [String: UIImage] = [:]
        for imageURL in Set(edition.entries.compactMap(\.imageURL)) {
            guard let remoteURL = URL(string: imageURL) else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: remoteURL), let image = UIImage(data: data) {
                images[imageURL] = image
            }
        }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 48
            func pageIfNeeded(_ height: CGFloat) {
                if y + height > 744 { context.beginPage(); y = 48 }
            }
            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 12) {
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                let size = (text as NSString).boundingRect(with: CGSize(width: 516, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).integral.size
                pageIfNeeded(size.height + spacing)
                (text as NSString).draw(in: CGRect(x: 48, y: y, width: 516, height: size.height + 4), withAttributes: attributes)
                y += size.height + spacing
            }
            context.beginPage()
            draw("DAILY BLURB", font: .systemFont(ofSize: 13, weight: .black), spacing: 8)
            draw(edition.monthLabel.uppercased(), font: .systemFont(ofSize: 34, weight: .black), spacing: 5)
            draw("A private recap for \(edition.groupName)", font: .italicSystemFont(ofSize: 15), color: .darkGray, spacing: 28)
            for entry in edition.entries.sorted(by: { $0.createdAt < $1.createdAt }) {
                draw(entry.prompt.uppercased(), font: .systemFont(ofSize: 11, weight: .bold), color: .darkGray, spacing: 5)
                draw(entry.answer.isEmpty ? "Photo of the Month" : entry.answer, font: .systemFont(ofSize: 17), spacing: 4)
                if let imageURL = entry.imageURL, let image = images[imageURL] {
                    pageIfNeeded(220)
                    let ratio = min(516 / image.size.width, 200 / image.size.height)
                    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    image.draw(in: CGRect(x: 48, y: y, width: size.width, height: size.height))
                    y += size.height + 10
                }
                draw("— \(entry.authorName)", font: .italicSystemFont(ofSize: 12), color: .darkGray, spacing: 22)
            }
        }
        return url
    }
}
