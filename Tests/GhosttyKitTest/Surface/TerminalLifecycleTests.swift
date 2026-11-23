import Foundation
@testable import GhosttyTerminal
import Testing

@MainActor
struct TerminalLifecycleTests {
    @Test
    func `generated configs stay in the host directory and follow controller lifetime`() throws {
        let manager = FileManager.default
        var controller: TerminalController? = TerminalController(theme: TerminalTheme()) { builder in
            builder.withFontSize(14)
        }
        let first = try #require(controller?.managedConfigURL)
        #expect(first.deletingLastPathComponent() == TerminalController.managedConfigDirectory)
        #expect(try String(contentsOf: first, encoding: .utf8).contains("font-size = 14"))

        #expect(controller?.updateConfigSource(.generated("font-size = 16")) == true)
        let replacement = try #require(controller?.managedConfigURL)
        #expect(!manager.fileExists(atPath: first.path))
        #expect(try String(contentsOf: replacement, encoding: .utf8).contains("font-size = 16"))

        controller = nil
        #expect(!manager.fileExists(atPath: replacement.path))
    }

    @Test
    func `rejected config file survives init and is not the base`() {
        let path = "/nonexistent-\(UUID().uuidString).conf"
        let controller = TerminalController(configFilePath: path)

        #expect(controller.lastConfigurationIssue?.contains("failed to load ghostty config template") == true)
        #expect(controller.currentConfigSource != .file(path))
        #expect(controller.renderedConfig.contains("background = F7F7F7"))

        // Clearing the theme resolves to the base, which is the default that
        // loaded — not the file that did not.
        #expect(controller.setTheme(TerminalTheme()))
        #expect(controller.currentConfigSource == .none)
        #expect(controller.renderedConfig == TerminalController.defaultRenderedConfig)
    }

    @Test
    func `updating the config source rebases theme rendering`() {
        let controller = TerminalController(
            configSource: .generated("cursor-style = block"),
            theme: .init(
                light: TerminalConfiguration().backgroundOpacity(0.91),
                dark: TerminalConfiguration().backgroundOpacity(0.47),
            ),
        )

        #expect(controller.updateConfigSource(.generated("font-size = 14")))
        #expect(controller.renderedConfig.contains("font-size = 14"))
        #expect(!controller.renderedConfig.contains("cursor-style = block"))
        #expect(controller.renderedConfig.contains("background-opacity = 0.91"))
        #expect(controller.lastConfigurationIssue == nil)

        controller.setColorScheme(.dark)

        #expect(controller.renderedConfig.contains("font-size = 14"))
        #expect(controller.renderedConfig.contains("background-opacity = 0.47"))
        #expect(!controller.renderedConfig.contains("background-opacity = 0.91"))
    }

    @Test
    func `relative config file path loads against the working directory`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "font-size = 14\n".write(
            to: directory.appendingPathComponent("ghostty.conf"),
            atomically: true,
            encoding: .utf8,
        )
        let previousDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(previousDirectory) }
        #expect(FileManager.default.changeCurrentDirectoryPath(directory.path))

        let controller = TerminalController(configFilePath: "ghostty.conf", theme: TerminalTheme())

        #expect(controller.lastConfigurationIssue == nil)
        #expect(controller.currentConfigSource == .file("ghostty.conf"))
        #expect(controller.renderedConfig == "font-size = 14\n")
    }

    @Test
    func `detaching a freed surface keeps a live replacement`() throws {
        let state = TerminalViewState()
        // Never freed or ticked: the only thing read off it is that it is live.
        let replacement = try TerminalSurface(#require(UnsafeMutableRawPointer(bitPattern: 0x1)))
        state.terminalDidAttachSurface(replacement)

        state.terminalDidDetachSurface()

        #expect(state.surface === replacement)
    }

    @Test
    func `failed surface creation does not retain bridge`() {
        let controller = TerminalController()
        let bridge = TerminalCallbackBridge()

        let surface = controller.createSurface(
            bridge: bridge,
            configuration: .init(),
        ) { _ in }

        #expect(surface == nil)
        #expect(controller.retainedBridgeCount == 0)
    }

    @Test
    func `switching controllers removes bridge from old controller`() {
        let oldController = TerminalController()
        let newController = TerminalController()
        let coordinator = TerminalSurfaceCoordinator()

        coordinator.isAttached = { false }
        oldController.retain(coordinator.bridge)
        #expect(oldController.retainedBridgeCount == 1)

        coordinator.controller = oldController
        #expect(oldController.retainedBridgeCount == 0)

        oldController.retain(coordinator.bridge)
        #expect(oldController.retainedBridgeCount == 1)

        coordinator.controller = newController

        #expect(oldController.retainedBridgeCount == 0)
        #expect(newController.retainedBridgeCount == 0)
    }

    @Test
    func `free surface removes retained bridge`() {
        let controller = TerminalController()
        let coordinator = TerminalSurfaceCoordinator()

        coordinator.isAttached = { false }
        coordinator.controller = controller

        controller.retain(coordinator.bridge)
        #expect(controller.retainedBridgeCount == 1)

        coordinator.freeSurface()

        #expect(controller.retainedBridgeCount == 0)
    }

    @Test
    func `suspended wakeup does not schedule render`() {
        let controller = TerminalController()
        let token = WakeupToken()
        var wakeups = 0

        controller.addWakeupObserver(
            ObjectIdentifier(token),
            shouldProcess: { false },
            onWakeup: { wakeups += 1 },
        )

        controller.handleWakeup()

        #expect(wakeups == 0)
    }

    @Test
    func `wakeup reaches every observer`() {
        let controller = TerminalController()
        let first = WakeupToken()
        let second = WakeupToken()
        var firstWakeups = 0
        var secondWakeups = 0

        controller.addWakeupObserver(
            ObjectIdentifier(first),
            shouldProcess: { true },
            onWakeup: { firstWakeups += 1 },
        )
        controller.addWakeupObserver(
            ObjectIdentifier(second),
            shouldProcess: { true },
            onWakeup: { secondWakeups += 1 },
        )

        controller.handleWakeup()

        #expect(firstWakeups == 1)
        #expect(secondWakeups == 1)
    }

    @Test
    func `removing one observer keeps the others awake`() {
        let controller = TerminalController()
        let first = WakeupToken()
        let second = WakeupToken()
        var firstWakeups = 0
        var secondWakeups = 0

        controller.addWakeupObserver(
            ObjectIdentifier(first),
            shouldProcess: { true },
            onWakeup: { firstWakeups += 1 },
        )
        controller.addWakeupObserver(
            ObjectIdentifier(second),
            shouldProcess: { false },
            onWakeup: { secondWakeups += 1 },
        )

        controller.removeWakeupObserver(ObjectIdentifier(second))
        controller.handleWakeup()

        #expect(firstWakeups == 1)
        #expect(secondWakeups == 0)
    }

    @Test
    func `a main-thread wakeup ticks on the next main-queue turn, never inside the call`() async {
        let controller = TerminalController()
        let token = WakeupToken()
        var wakeups = 0
        controller.addWakeupObserver(
            ObjectIdentifier(token),
            shouldProcess: { true },
            onWakeup: { wakeups += 1 },
        )
        let userdata = Unmanaged.passUnretained(controller).toOpaque()

        // As Ghostty calls it from inside a C call the main thread made (a
        // synchronous draw holding the renderer's draw mutex): twice, since
        // one call can push more than one message.
        #expect(Thread.isMainThread)
        terminalControllerWakeupCallback(userdata: userdata)
        terminalControllerWakeupCallback(userdata: userdata)
        #expect(wakeups == 0, "a main-thread wakeup ticked before the C call returned")

        // The main queue is FIFO: once this turn has run, the scheduled tick has.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(wakeups == 1, "the wakeups were not ticked once on the next main-queue turn")

        // The gate is open again, so a later wakeup schedules its own tick.
        terminalControllerWakeupCallback(userdata: userdata)
        #expect(wakeups == 1)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(wakeups == 2)
    }

    @Test
    func `application active state controls immediate ticks`() async {
        let coordinator = TerminalSurfaceCoordinator()
        var renders = 0

        coordinator.isAttached = { true }
        coordinator.onPostRender = {
            renders += 1
        }

        coordinator.setApplicationActive(false)
        coordinator.requestImmediateTick()
        await Task.yield()

        #expect(renders == 0)

        coordinator.setApplicationActive(true)
        await Task.yield()

        #expect(renders == 1)
    }
}

private final class WakeupToken {}
