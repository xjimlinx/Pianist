import QtQuick
import QtTest
import QtCore as QtCore

TestCase {
    id: testCase
    name: "SharedSettingsRuntime"

    readonly property string settingsPath:
        QtCore.StandardPaths.writableLocation(QtCore.StandardPaths.TempLocation)
        + "/pianist-shared-settings-test-" + Date.now() + ".conf"

    QtCore.Settings {
        id: firstInstance
        location: testCase.settingsPath
        category: "Data"
    }

    QtCore.Settings {
        id: secondInstance
        location: testCase.settingsPath
        category: "Data"
    }

    function test_instancesShareOneDocument() {
        const payload = '{"version":2,"tasks":[]}'
        firstInstance.setValue("documentJson", payload)
        firstInstance.sync()
        secondInstance.sync()
        compare(String(secondInstance.value("documentJson", "")), payload)
    }

    function cleanupTestCase() {
        firstInstance.setValue("documentJson", "")
        firstInstance.setValue("backupJson", "")
        firstInstance.sync()
    }
}
