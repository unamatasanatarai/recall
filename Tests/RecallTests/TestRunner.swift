import Foundation

@main
struct TestRunner {
    static func main() {
        print("==> Running Recall Unit Tests...")
        var passedCount = 0
        var failedCount = 0

        func runTest(_ name: String, _ testBlock: () throws -> Void) {
            print("  Running \(name)...", terminator: " ")
            do {
                try testBlock()
                print("✅ PASSED")
                passedCount += 1
            } catch {
                print("❌ FAILED: \(error)")
                failedCount += 1
            }
        }

        // --- Section 1: SettingsManagerTests ---
        runTest("SettingsManager.testDefaultValuesInitialization_exportsDirectoryPath") {
            try SettingsManagerTests.testDefaultValuesInitialization_exportsDirectoryPath()
        }
        runTest("SettingsManager.testDefaultSizeLimit") {
            try SettingsManagerTests.testDefaultSizeLimit()
        }
        runTest("SettingsManager.testDefaultTimeLimit") {
            try SettingsManagerTests.testDefaultTimeLimit()
        }
        runTest("SettingsManager.testUserDefaultsPersistence_exportsDirectoryPath") {
            try SettingsManagerTests.testUserDefaultsPersistence_exportsDirectoryPath()
        }
        runTest("SettingsManager.testUserDefaultsPersistence_maxStorageMB") {
            try SettingsManagerTests.testUserDefaultsPersistence_maxStorageMB()
        }
        runTest("SettingsManager.testUserDefaultsPersistence_maxStorageMinutes") {
            try SettingsManagerTests.testUserDefaultsPersistence_maxStorageMinutes()
        }
        runTest("SettingsManager.testStorageConfigByteCalculation_variousValues") {
            try SettingsManagerTests.testStorageConfigByteCalculation_variousValues()
        }
        runTest("SettingsManager.testStorageConfigSecondCalculation_variousValues") {
            try SettingsManagerTests.testStorageConfigSecondCalculation_variousValues()
        }
        runTest("SettingsManager.testTildePathExpansion") {
            try SettingsManagerTests.testTildePathExpansion()
        }
        runTest("SettingsManager.testExportDirectoryAutoCreation") {
            try SettingsManagerTests.testExportDirectoryAutoCreation()
        }
        runTest("SettingsManager.testSettingsChangedCallback_maxStorageMB") {
            try SettingsManagerTests.testSettingsChangedCallback_maxStorageMB()
        }
        runTest("SettingsManager.testSettingsChangedCallback_maxStorageMinutes") {
            try SettingsManagerTests.testSettingsChangedCallback_maxStorageMinutes()
        }
        runTest("SettingsManager.testResetToDefaults_resetsProperties") {
            try SettingsManagerTests.testResetToDefaults_resetsProperties()
        }

        // --- Section 2 & 3: ChunkManagerTests ---
        runTest("ChunkManager.testDirectoryCreation") {
            try ChunkManagerTests.testDirectoryCreation()
        }
        runTest("ChunkManager.testLoadExistingFiles_mp4AndIgnoreNonMp4") {
            try ChunkManagerTests.testLoadExistingFiles_mp4AndIgnoreNonMp4()
        }
        runTest("ChunkManager.testLoadExistingFiles_purgeCorrupt") {
            try ChunkManagerTests.testLoadExistingFiles_purgeCorrupt()
        }
        runTest("ChunkManager.testParseDateFromFilename") {
            try ChunkManagerTests.testParseDateFromFilename()
        }
        runTest("ChunkManager.testFallbackCreationDate") {
            try ChunkManagerTests.testFallbackCreationDate()
        }
        runTest("ChunkManager.testSortOrder") {
            try ChunkManagerTests.testSortOrder()
        }
        runTest("ChunkManager.testTotalDurationCalculation") {
            try ChunkManagerTests.testTotalDurationCalculation()
        }
        runTest("ChunkManager.testEnforceLimits_purgesOldestWhenOverSizeBytes") {
            try ChunkManagerTests.testEnforceLimits_purgesOldestWhenOverSizeBytes()
        }
        runTest("ChunkManager.testEnforceLimits_purgesOldestWhenOverDuration") {
            try ChunkManagerTests.testEnforceLimits_purgesOldestWhenOverDuration()
        }
        runTest("ChunkManager.testEnforceLimits_multiChunkSequentialPurge") {
            try ChunkManagerTests.testEnforceLimits_multiChunkSequentialPurge()
        }
        runTest("ChunkManager.testEnforceLimits_zeroLimitHandling") {
            try ChunkManagerTests.testEnforceLimits_zeroLimitHandling()
        }
        runTest("ChunkManager.testPurgeAllChunks_removesAllRegisteredFiles") {
            try ChunkManagerTests.testPurgeAllChunks_removesAllRegisteredFiles()
        }
        runTest("ChunkManager.testRegisterZeroByteChunk") {
            try ChunkManagerTests.testRegisterZeroByteChunk()
        }
        runTest("ChunkManager.testRegisterCorruptChunk") {
            try ChunkManagerTests.testRegisterCorruptChunk()
        }

        // --- Section 4: ChunkManagerExportTests ---
        runTest("ChunkManagerExport.testExportClip_emptyChunkGuard") {
            try ChunkManagerExportTests.testExportClip_emptyChunkGuard()
        }
        runTest("ChunkManagerExport.testExportClip_chunkSelectionAndTrimming") {
            try ChunkManagerExportTests.testExportClip_chunkSelectionAndTrimming()
        }
        runTest("ChunkManagerExport.testExportClip_avfoundationFallbackWhenFFmpegFails") {
            try ChunkManagerExportTests.testExportClip_avfoundationFallbackWhenFFmpegFails()
        }
        runTest("ChunkManagerExport.testExportClip_avfoundationFallbackWithRealMP4Asset") {
            try ChunkManagerExportTests.testExportClip_avfoundationFallbackWithRealMP4Asset()
        }

        // --- Section 5: FFmpegRunnerTests ---
        runTest("FFmpegRunner.testCandidatePathDiscovery") {
            try FFmpegRunnerTests.testCandidatePathDiscovery()
        }
        runTest("FFmpegRunner.testMissingBinaryHandling") {
            try FFmpegRunnerTests.testMissingBinaryHandling()
        }
        runTest("FFmpegRunner.testConcatCommandFormatting") {
            try FFmpegRunnerTests.testConcatCommandFormatting()
        }
        runTest("FFmpegRunner.testTrimArgumentFormatting") {
            try FFmpegRunnerTests.testTrimArgumentFormatting()
        }

        // --- Section 6: VideoMetadataProviderTests ---
        runTest("VideoMetadataProvider.testValidMP4Validation") {
            try VideoMetadataProviderTests.testValidMP4Validation()
        }
        runTest("VideoMetadataProvider.testZeroDurationValidation") {
            try VideoMetadataProviderTests.testZeroDurationValidation()
        }
        runTest("VideoMetadataProvider.testMissingVideoTrackValidation") {
            try VideoMetadataProviderTests.testMissingVideoTrackValidation()
        }
        runTest("VideoMetadataProvider.testInfiniteDurationGuard") {
            try VideoMetadataProviderTests.testInfiniteDurationGuard()
        }

        // --- Section 7: RecorderEngineTests ---
        runTest("RecorderEngine.testInitialIdleState") {
            try RecorderEngineTests.testInitialIdleState()
        }
        runTest("RecorderEngine.testChunkFileNaming") {
            try RecorderEngineTests.testChunkFileNaming()
        }
        runTest("RecorderEngine.testLogFileRotation") {
            try RecorderEngineTests.testLogFileRotation()
        }
        runTest("RecorderEngine.testFlushCurrentChunkAction") {
            try RecorderEngineTests.testFlushCurrentChunkAction()
        }
        runTest("RecorderEngine.testStopStreamAction") {
            try RecorderEngineTests.testStopStreamAction()
        }

        // --- Section 8: OverlayHUDWindowTests ---
        runTest("OverlayHUDWindow.testHUDWindowProperties") {
            try OverlayHUDWindowTests.testHUDWindowProperties()
        }
        runTest("OverlayHUDWindow.testCoordinateConversion") {
            try OverlayHUDWindowTests.testCoordinateConversion()
        }
        runTest("OverlayHUDWindow.testTaperedBeamPathGeneration") {
            try OverlayHUDWindowTests.testTaperedBeamPathGeneration()
        }
        runTest("OverlayHUDWindow.testTimeOffsetFormatter") {
            try OverlayHUDWindowTests.testTimeOffsetFormatter()
        }
        runTest("OverlayHUDWindow.testViewModelReactivity") {
            try OverlayHUDWindowTests.testViewModelReactivity()
        }

        // --- Section 9: MenuBarManagerTests ---
        runTest("MenuBarManager.testStatusItemCreation") {
            try MenuBarManagerTests.testStatusItemCreation()
        }
        runTest("MenuBarManager.testTemplateIconMode") {
            try MenuBarManagerTests.testTemplateIconMode()
        }
        runTest("MenuBarManager.testDragDownDistanceClamping") {
            try MenuBarManagerTests.testDragDownDistanceClamping()
        }
        runTest("MenuBarManager.testStepQuantization") {
            try MenuBarManagerTests.testStepQuantization()
        }
        runTest("MenuBarManager.testDragReleaseExportTrigger") {
            try MenuBarManagerTests.testDragReleaseExportTrigger()
        }

        // --- Section 10: SettingsViewTests ---
        runTest("SettingsView.testUsageStatsFormatting") {
            try SettingsViewTests.testUsageStatsFormatting()
        }
        runTest("SettingsView.testUsageStatsSizeFormatting") {
            try SettingsViewTests.testUsageStatsSizeFormatting()
        }
        runTest("SettingsView.testTotalClipsCountUpdate") {
            try SettingsViewTests.testTotalClipsCountUpdate()
        }
        runTest("SettingsView.testStepperIncrements") {
            try SettingsViewTests.testStepperIncrements()
        }
        runTest("SettingsView.testResetStorageDefaults") {
            try SettingsViewTests.testResetStorageDefaults()
        }

        // --- Section 11: ConcurrencyTests ---
        runTest("Concurrency.testConcurrentRegisterChunk") {
            try ConcurrencyTests.testConcurrentRegisterChunk()
        }
        runTest("Concurrency.testConcurrentPurgeAndLimitEnforcement") {
            try ConcurrencyTests.testConcurrentPurgeAndLimitEnforcement()
        }
        runTest("Concurrency.testThreadSafeDurationAccess") {
            try ConcurrencyTests.testThreadSafeDurationAccess()
        }
        runTest("Concurrency.testConcurrentLogFileWriting") {
            try ConcurrencyTests.testConcurrentLogFileWriting()
        }

        // --- Section 12: FileSystemErrorTests ---
        runTest("FileSystemError.testPermissionDeniedDirectoryHandling") {
            try FileSystemErrorTests.testPermissionDeniedDirectoryHandling()
        }
        runTest("FileSystemError.testDiskFullAttributesHandling") {
            try FileSystemErrorTests.testDiskFullAttributesHandling()
        }
        runTest("FileSystemError.testFileRemovalErrorResilience") {
            try FileSystemErrorTests.testFileRemovalErrorResilience()
        }
        runTest("FileSystemError.testNonCreatableExportDirectoryFallback") {
            try FileSystemErrorTests.testNonCreatableExportDirectoryFallback()
        }

        // --- Section 13: AVFoundationEdgeCasesTests ---
        runTest("AVFoundationEdgeCases.testUnreadableAssetResilience") {
            try AVFoundationEdgeCasesTests.testUnreadableAssetResilience()
        }
        runTest("AVFoundationEdgeCases.testAudioFreeCompositionHandling") {
            try AVFoundationEdgeCasesTests.testAudioFreeCompositionHandling()
        }
        runTest("AVFoundationEdgeCases.testUnsupportedCodecErrorHandling") {
            try AVFoundationEdgeCasesTests.testUnsupportedCodecErrorHandling()
        }

        // --- Section 14: SettingsWindowControllerTests ---
        runTest("SettingsWindowController.testWindowSingletonInstanceReuse") {
            try SettingsWindowControllerTests.testWindowSingletonInstanceReuse()
        }
        runTest("SettingsWindowController.testEscapeKeyWindowClosure") {
            try SettingsWindowControllerTests.testEscapeKeyWindowClosure()
        }
        runTest("SettingsWindowController.testPreferencesResetButtonAction") {
            try SettingsWindowControllerTests.testPreferencesResetButtonAction()
        }

        // --- Section 15: BuildAutomationTests ---
        runTest("BuildAutomation.testIncrementalCompilationLogic") {
            try BuildAutomationTests.testIncrementalCompilationLogic()
        }
        runTest("BuildAutomation.testPlistVersionEmbedding") {
            try BuildAutomationTests.testPlistVersionEmbedding()
        }
        runTest("BuildAutomation.testDMGBackgroundDimensionCheck") {
            try BuildAutomationTests.testDMGBackgroundDimensionCheck()
        }
        runTest("BuildAutomation.testReleaseScriptSemanticBumping") {
            try BuildAutomationTests.testReleaseScriptSemanticBumping()
        }

        // --- Section 16: RecorderEngineDeepCoverageTests ---
        runTest("RecorderEngineDeepCoverage.testAlreadyRecordingGuard") {
            try RecorderEngineDeepCoverageTests.testAlreadyRecordingGuard()
        }
        runTest("RecorderEngineDeepCoverage.testPermissionPreflightMissing") {
            try RecorderEngineDeepCoverageTests.testPermissionPreflightMissing()
        }
        runTest("RecorderEngineDeepCoverage.testPermissionPreflightGranted") {
            try RecorderEngineDeepCoverageTests.testPermissionPreflightGranted()
        }
        runTest("RecorderEngineDeepCoverage.testHandleFrameDropAndIdle") {
            try RecorderEngineDeepCoverageTests.testHandleFrameDropAndIdle()
        }
        runTest("RecorderEngineDeepCoverage.testHandleFrameNilSurface") {
            try RecorderEngineDeepCoverageTests.testHandleFrameNilSurface()
        }
        runTest("RecorderEngineDeepCoverage.testStartNewChunkAndRotateChunk") {
            try RecorderEngineDeepCoverageTests.testStartNewChunkAndRotateChunk()
        }
        runTest("RecorderEngineDeepCoverage.testStreamStopCleanup") {
            try RecorderEngineDeepCoverageTests.testStreamStopCleanup()
        }
        runTest("RecorderEngineDeepCoverage.testLogFileOverSizeRotation") {
            try RecorderEngineDeepCoverageTests.testLogFileOverSizeRotation()
        }
        runTest("RecorderEngineDeepCoverage.testFlushCurrentChunkNilWriter") {
            try RecorderEngineDeepCoverageTests.testFlushCurrentChunkNilWriter()
        }
        runTest("RecorderEngineDeepCoverage.testActiveChunkFlushAndStopStream") {
            try RecorderEngineDeepCoverageTests.testActiveChunkFlushAndStopStream()
        }
        runTest("RecorderEngineDeepCoverage.testHandleFrameRotationAndWriting") {
            try RecorderEngineDeepCoverageTests.testHandleFrameRotationAndWriting()
        }
        runTest("RecorderEngineDeepCoverage.testHandleFrameWithIOSurface") {
            try RecorderEngineDeepCoverageTests.testHandleFrameWithIOSurface()
        }

        // --- Section 17: ChunkManagerAdvancedExportTests ---
        runTest("ChunkManagerAdvancedExport.testSubSecondTargetClamping") {
            try ChunkManagerAdvancedExportTests.testSubSecondTargetClamping()
        }
        runTest("ChunkManagerAdvancedExport.testExportOffsetLargerThanTotalStore") {
            try ChunkManagerAdvancedExportTests.testExportOffsetLargerThanTotalStore()
        }
        runTest("ChunkManagerAdvancedExport.testSingleNewestChunkOverLimitPurge") {
            try ChunkManagerAdvancedExportTests.testSingleNewestChunkOverLimitPurge()
        }

        // --- Section 18: OverlayHUDWindowRenderTests ---
        runTest("OverlayHUDWindowRender.testZeroDistanceBeamPath") {
            try OverlayHUDWindowRenderTests.testZeroDistanceBeamPath()
        }
        runTest("OverlayHUDWindowRender.testBeamEndWidthClamping") {
            try OverlayHUDWindowRenderTests.testBeamEndWidthClamping()
        }
        runTest("OverlayHUDWindowRender.testSubMinuteHUDTimeFormatting") {
            try OverlayHUDWindowRenderTests.testSubMinuteHUDTimeFormatting()
        }
        runTest("OverlayHUDWindowRender.testOrderOutHUDAction") {
            try OverlayHUDWindowRenderTests.testOrderOutHUDAction()
        }
        runTest("OverlayHUDWindowRender.testRenderOverlayHUDBeamView") {
            try OverlayHUDWindowRenderTests.testRenderOverlayHUDBeamView()
        }

        // --- Section 19: MenuBarPreferencesIntegrationTests ---
        runTest("MenuBarPreferencesIntegration.testPurgeRecordingsConfirmed") {
            try MenuBarPreferencesIntegrationTests.testPurgeRecordingsConfirmed()
        }
        runTest("MenuBarPreferencesIntegration.testPurgeRecordingsCancelled") {
            try MenuBarPreferencesIntegrationTests.testPurgeRecordingsCancelled()
        }
        runTest("MenuBarPreferencesIntegration.testOpenSettingsAndQuitApp") {
            try MenuBarPreferencesIntegrationTests.testOpenSettingsAndQuitApp()
        }
        runTest("MenuBarPreferencesIntegration.testPreferencesDirectoryPickerConfirmed") {
            try MenuBarPreferencesIntegrationTests.testPreferencesDirectoryPickerConfirmed()
        }
        runTest("MenuBarPreferencesIntegration.testPreferencesDirectoryPickerCancelled") {
            try MenuBarPreferencesIntegrationTests.testPreferencesDirectoryPickerCancelled()
        }

        runTest("MenuBarPreferencesIntegration.testQuitApplicationStreamTearDown") {
            try MenuBarPreferencesIntegrationTests.testQuitApplicationStreamTearDown()
        }
        runTest("MenuBarPreferencesIntegration.testMenuBarManagerMouseEventHandling") {
            try MenuBarPreferencesIntegrationTests.testMenuBarManagerMouseEventHandling()
        }
        runTest("MenuBarPreferencesIntegration.testTriggerExport") {
            try MenuBarPreferencesIntegrationTests.testTriggerExport()
        }
        runTest("MenuBarPreferencesIntegration.testSettingsWindowControllerCloseWindow") {
            try MenuBarPreferencesIntegrationTests.testSettingsWindowControllerCloseWindow()
        }
        runTest("MenuBarPreferencesIntegration.testDefaultProtocolImplementations") {
            try MenuBarPreferencesIntegrationTests.testDefaultProtocolImplementations()
        }

        // --- Section 20: SystemProcessAutomationTests ---
        runTest("SystemProcessAutomation.testTCCPermissionRevocationCommand") {
            try SystemProcessAutomationTests.testTCCPermissionRevocationCommand()
        }
        runTest("SystemProcessAutomation.testBuildCommandOutputBinaryCheck") {
            try SystemProcessAutomationTests.testBuildCommandOutputBinaryCheck()
        }
        runTest("SystemProcessAutomation.testAppDelegateLifecycle") {
            try SystemProcessAutomationTests.testAppDelegateLifecycle()
        }
        runTest("SystemProcessAutomation.testRecallAppInstantiation") {
            try SystemProcessAutomationTests.testRecallAppInstantiation()
        }

        print("\nSummary: \(passedCount) passed, \(failedCount) failed.\n")
        if failedCount > 0 {
            exit(1)
        }
    }
}
