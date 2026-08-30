import QtQuick
import QtTest
import "../WorkspaceModel.js" as WorkspaceModel

TestCase {
    name: "WorkspaceModel"

    function test_ordersOnlyBoundedOrdinaryWorkspaces() {
        var workspaces = [
            {id: 8, name: "8"},
            {id: -99, name: "special:scratch"},
            {id: 2, name: "2"},
            {id: 1000, name: "1000"},
            {id: 2, name: "duplicate"},
            {id: 0, name: "named:writing"}
        ];
        var entries = WorkspaceModel.ordinaryWorkspaces(workspaces, [], {id: 8});
        compare(entries.length, 2);
        compare(entries[0].id, 2);
        compare(entries[1].id, 8);
        verify(!entries[0].active);
        verify(entries[1].active);
    }

    function test_reportsOccupancyFromRealWindows() {
        var workspaces = [{id: 1, name: "1"}, {id: 4, name: "4"}];
        var windows = [
            {workspace: {id: 4}},
            {workspace: {id: 4}},
            {workspace: {id: -99, name: "special:scratch"}}
        ];
        var entries = WorkspaceModel.ordinaryWorkspaces(workspaces, windows, {id: 1});
        compare(entries[0].count, 0);
        verify(!entries[0].occupied);
        compare(entries[1].count, 2);
        verify(entries[1].occupied);
    }

    function test_cyclesInStableOrder() {
        var entries = [{id: 1}, {id: 3}, {id: 8}];
        compare(WorkspaceModel.cycleWorkspaceId(entries, 1, 1), 3);
        compare(WorkspaceModel.cycleWorkspaceId(entries, 1, -1), 8);
        compare(WorkspaceModel.cycleWorkspaceId(entries, 99, 1), 1);
    }

    function test_moveRequestRequiresAddressAndExistingWorkspace() {
        var entries = [{id: 1}, {id: 4}];
        var valid = WorkspaceModel.moveRequest("0xABC123", 4, entries);
        verify(valid.ok);
        compare(valid.address, "0xabc123");
        compare(valid.workspaceId, 4);
        verify(!WorkspaceModel.moveRequest("not-an-address", 4, entries).ok);
        verify(!WorkspaceModel.moveRequest("0xabc123", 3, entries).ok);
        verify(!WorkspaceModel.moveRequest("0xabc123", -99, entries).ok);
    }
}
