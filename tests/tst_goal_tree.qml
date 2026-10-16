import QtQuick
import QtTest

import "../package/contents/ui" as Pianist

TestCase {
    id: testCase
    name: "GoalTreeRuntime"
    width: 1280
    height: 900
    when: windowShown

    property var sampleGoal: ({
        "id": 1,
        "title": "复杂路线布局回归测试",
        "description": "覆盖长文本、并行节点与跨层前置关系",
        "created_at": 1,
        "completed_at": null,
        "terminated_at": null,
        "nodes": [
            { "id": 1, "title": "准备一份包含较长标题的基础方案", "description": "用于触发文本换行。", "requires": [], "shape": -1, "created_at": 1, "completed_at": 2 },
            { "id": 2, "title": "并行任务 A", "description": "第一条并行路线。", "requires": [1], "shape": 2, "created_at": 2, "completed_at": null },
            { "id": 3, "title": "并行任务 B", "description": "第二条并行路线。", "requires": [1], "shape": 0, "created_at": 3, "completed_at": null },
            { "id": 4, "title": "并行任务 C", "description": "第三条并行路线。", "requires": [1], "shape": 1, "created_at": 4, "completed_at": null },
            { "id": 5, "title": "汇总 A 与 B", "description": "测试多个前置节点。", "requires": [2, 3], "shape": -1, "created_at": 5, "completed_at": null },
            { "id": 6, "title": "跨层依赖", "description": "同时依赖较早节点和汇总节点。", "requires": [2, 5], "shape": 2, "created_at": 6, "completed_at": null },
            { "id": 7, "title": "最终验收", "description": "路线末端节点。", "requires": [4, 6], "shape": -1, "created_at": 7, "completed_at": null }
        ]
    })

    Pianist.GoalTree {
        id: tree
        anchors.fill: parent
        goal: testCase.sampleGoal
        nodeScale: 1
        glassSurface: "#cc202124"
        glassRaised: "#ee303134"
        glassBorder: "#66888888"
        glassShadow: "#66000000"
        accentWash: "#335a8dee"
    }

    function test_layoutStaysFinite() {
        wait(100)
        verify(isFinite(tree.layoutData.width))
        verify(isFinite(tree.layoutData.height))
        verify(tree.layoutData.width > 0)
        verify(tree.layoutData.height > 0)

        const stableWidth = tree.layoutData.width
        const stableHeight = tree.layoutData.height
        wait(250)
        compare(tree.layoutData.width, stableWidth)
        compare(tree.layoutData.height, stableHeight)
    }

    function test_invalidScaleFallsBack() {
        tree.nodeScale = NaN
        wait(50)
        compare(tree.effectiveNodeScale, 1)
        verify(isFinite(tree.nodeWidth))
        verify(isFinite(tree.nodeHeight))
        verify(isFinite(tree.layoutData.width))
        verify(isFinite(tree.layoutData.height))
        tree.nodeScale = 1
    }
}
