import SwiftUI

struct BlurbPost: Identifiable {
    let id = UUID()
    let author: String
    let timeLabel: String
    let answer: String
    var likeCount: Int
    var commentCount: Int
    var isLiked = false

    static let samples = [
        BlurbPost(
            author: "Jenna",
            timeLabel: "4 hours late",
            answer: "Starting to love the summer weather. It feels like my seasonal depression is gone!",
            likeCount: 4,
            commentCount: 2
        ),
        BlurbPost(
            author: "Daniel",
            timeLabel: "2 hours late",
            answer: "I slept in until 11 am.",
            likeCount: 6,
            commentCount: 18
        ),
        BlurbPost(
            author: "Oscar",
            timeLabel: "On time",
            answer: "I finally cleaned the kitchen and made coffee before class.",
            likeCount: 3,
            commentCount: 1
        )
    ]
}

struct ContentView: View {
    @State private var showingNewPost = false
    @State private var selectedPost: BlurbPost?
    @State private var posts = BlurbPost.samples

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        dailyPromptButton
                        feed
                    }
                    .padding(.vertical)
                }
            }
            .sheet(isPresented: $showingNewPost) {
                NewPostView { answer in
                    posts.insert(
                        BlurbPost(
                            author: "You",
                            timeLabel: "Just now",
                            answer: answer,
                            likeCount: 0,
                            commentCount: 0
                        ),
                        at: 0
                    )
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedPost) { post in
                CommentsView(post: post)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Good morning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("College Roommates")
                    .font(.title.bold())
            }

            Spacer()

            Image(systemName: "bookmark.fill")
                .foregroundStyle(.indigo)
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
        .padding(.horizontal)
    }

    private var dailyPromptButton: some View {
        Button {
            showingNewPost = true
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TODAY'S BLURB")
                        .font(.caption.bold())
                        .tracking(1)
                        .opacity(0.8)

                    Text("What changed from yesterday to today?")
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.title3.bold())
                    .padding(14)
                    .background(.white.opacity(0.22), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(
                LinearGradient(
                    colors: [.indigo, .purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .shadow(color: .indigo.opacity(0.35), radius: 18, y: 10)
        }
        .padding(.horizontal)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECENT BLURBS")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(posts) { post in
                PostCard(
                    post: post,
                    toggleLike: { toggleLike(for: post.id) },
                    showComments: { selectedPost = post }
                )
            }
        }
        .padding(.horizontal)
    }

    private func toggleLike(for id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].isLiked.toggle()
        posts[index].likeCount += posts[index].isLiked ? 1 : -1
    }
}

struct PostCard: View {
    let post: BlurbPost
    let toggleLike: () -> Void
    let showComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(post.author) in College Roommates")
                        .font(.headline)

                    Text(post.timeLabel)
                        .font(.subheadline)
                        .foregroundStyle(post.timeLabel == "On time" ? .green : .secondary)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            Text("Answering today's blurb")
                .font(.caption.bold())
                .foregroundStyle(.indigo)

            Text(post.answer)
                .font(.body)

            HStack(spacing: 18) {
                Button(action: toggleLike) {
                    Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(post.isLiked ? .red : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: showComments) {
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
    }
}

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    let onPost: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 20) {
                    Text("What changed from yesterday to today?")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 26)
                        )

                    TextEditor(text: $answer)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 220)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.4), lineWidth: 1)
                        }

                    Button {
                        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedAnswer.isEmpty else { return }
                        onPost(trimmedAnswer)
                        dismiss()
                    } label: {
                        Text("Post Blurb")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.black.opacity(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 0.82), in: Capsule())
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let post: BlurbPost
    @State private var newComment = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 18) {
                    Text("Comments on \(post.author)'s Blurb")
                        .font(.headline)

                    ContentUnavailableView(
                        "No comments yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Be the first roommate to respond.")
                    )

                    HStack {
                        TextField("Add a comment", text: $newComment)
                            .textFieldStyle(.roundedBorder)

                        Button("Send") {
                            newComment = ""
                        }
                        .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.indigo.opacity(0.20),
                Color.purple.opacity(0.10),
                Color.blue.opacity(0.14),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
