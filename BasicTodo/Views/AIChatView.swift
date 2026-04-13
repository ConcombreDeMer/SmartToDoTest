import SwiftUI

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AIChatViewModel

    init(viewModel: AIChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isGenerating {
                                ProgressView("Thinking…")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(using: proxy)
                    }
                    .onChange(of: viewModel.isGenerating) {
                        scrollToBottom(using: proxy)
                    }
                    .onAppear {
                        scrollToBottom(using: proxy)
                    }
                }

                Divider()

                if let message = viewModel.availability.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                if let speechMessage = viewModel.speechMessage {
                    Text(speechMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, viewModel.availability.message == nil ? 12 : 4)
                }

                if viewModel.isRecording {
                    Text("Listening… Keep holding to record, then release to stop.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)
                } else {
                    Text(viewModel.recordingHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                composer
                    .padding()
                    .background(.bar)
            }
            .navigationTitle("Task Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        viewModel.stopRecording()
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.refreshAvailability()
            await viewModel.syncTasks()
        }
        .onDisappear {
            viewModel.stopRecording()
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Ask the assistant", text: $viewModel.draftMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
                .disabled(viewModel.isUnavailable || viewModel.isGenerating)
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Group {
                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(viewModel.isMicrophoneDisabled ? .secondary : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.isRecording ? Color.red : Color(.tertiarySystemFill))
                    )
                    .foregroundStyle(viewModel.isRecording ? .white : (viewModel.isMicrophoneDisabled ? .secondary : .primary))
            }
            .frame(width: 36, height: 36)
            .opacity(viewModel.isMicrophoneDisabled ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(!viewModel.isMicrophoneDisabled)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !viewModel.isRecording else { return }
                        Task { await viewModel.startRecording() }
                    }
                    .onEnded { _ in
                        viewModel.stopRecording()
                    }
            )

            Button("Send") {
                Task { await viewModel.sendMessage() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSendDisabled)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(message.content)
                .frame(
                    maxWidth: .infinity,
                    alignment: message.role == .user ? .trailing : .leading
                )
                .padding(12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(foregroundColor)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleColor: Color {
        message.role == .user ? .black : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
