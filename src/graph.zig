const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const NodeIndex = usize;
const EdgeIndex = usize;

const Direction = enum(usize) {
    const Self = @This();

    Outgoing,
    Incoming,

    fn opposite(self: Self) Self {
        return @intToEnum(Self, (@enumToInt(self) + 1) % 2);
    }
};

const SortError = error{CycleFound};

/// data can be accessed by going like graph.nodes.items[some_idx]
pub fn Graph(comptime N: type, comptime E: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            weight: N,

            next: ?NodeIndex,
            in_use: bool,

            edges: [2]?EdgeIndex,
        };

        const Edge = struct {
            weight: E,

            start_node: NodeIndex,
            end_node: NodeIndex,

            next: [2]?EdgeIndex,
            in_use: bool,
        };

        const EdgeReference = struct {
            idx: EdgeIndex,
            edge: *Edge,
        };

        const EdgeIterator = struct {
            graph: *const Self,
            curr_idx: ?EdgeIndex,
            direction: Direction,

            pub fn next(self: *EdgeIterator) ?EdgeReference {
                const idx = self.curr_idx orelse return null;
                const edge = &self.graph.edges.items[idx];
                self.curr_idx = edge.next[@enumToInt(self.direction)];
                return EdgeReference{
                    .edge = edge,
                    .idx = idx,
                };
            }
        };

        nodes: ArrayList(Node),
        edges: ArrayList(Edge),
        next_node: ?NodeIndex,
        next_edge: ?EdgeIndex,

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .nodes = ArrayList(Node).init(allocator),
                .edges = ArrayList(Edge).init(allocator),
                .next_node = null,
                .next_edge = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
            self.edges.deinit();
        }

        fn removeEdgeFromNode(
            self: *Self,
            node_idx: NodeIndex,
            edge_idx: EdgeIndex,
            direction: Direction,
        ) void {
            const edge = &self.edges.items[edge_idx];
            var node = &self.nodes.items[node_idx];
            const dir = @enumToInt(direction);

            if (node.edges[dir]) |head_idx| {
                if (head_idx == edge_idx) {
                    node.edges[dir] = edge.next[dir];
                } else {
                    var find_idx: ?usize = head_idx;
                    while (find_idx) |find_idx_| {
                        var find_edge = self.edges.items[find_idx_];

                        if (find_edge.next[dir] == edge_idx) {
                            find_edge.next = edge.next;
                            break;
                        }

                        find_idx = find_edge.next[dir];
                    }
                }
            }
        }

        pub fn addNode(self: *Self, weight: N) !NodeIndex {
            const idx = if (self.next_node) |idx| blk: {
                var node = &self.nodes.items[idx];
                self.next_node = node.next;
                break :blk idx;
            } else blk: {
                const idx = self.nodes.items.len;
                try self.nodes.append(undefined);
                break :blk idx;
            };

            self.nodes.items[idx] = .{
                .weight = weight,
                .next = null,
                .in_use = true,
                .edges = .{ null, null },
            };

            return idx;
        }

        pub fn removeNode(self: *Self, idx: NodeIndex) void {
            {
                var iter = self.edgesDirected(idx, .Outgoing);
                while (iter.next()) |ref| {
                    self.removeEdgeFromNode(ref.edge.end_node, ref.idx, .Incoming);
                }
            }

            {
                var iter = self.edgesDirected(idx, .Incoming);
                while (iter.next()) |ref| {
                    self.removeEdgeFromNode(ref.edge.start_node, ref.idx, .Outgoing);
                }
            }

            var dead_node = &self.nodes.items[idx];
            dead_node.in_use = false;
            dead_node.next = self.next_node;
            self.next_node = idx;
        }

        pub fn addEdge(
            self: *Self,
            start_idx: NodeIndex,
            end_idx: NodeIndex,
            weight: E,
        ) !EdgeIndex {
            var node_start = &self.nodes.items[start_idx];
            var node_end = &self.nodes.items[end_idx];

            const idx = if (self.next_edge) |idx| blk: {
                var edge = &self.edges.items[idx];
                self.next_edge = edge.next[0];
                break :blk idx;
            } else blk: {
                const idx = self.edges.items.len;
                try self.edges.append(undefined);
                break :blk idx;
            };

            self.edges.items[idx] = .{
                .weight = weight,
                .start_node = start_idx,
                .end_node = end_idx,
                .next = .{
                    node_start.edges[@enumToInt(Direction.Outgoing)],
                    node_end.edges[@enumToInt(Direction.Incoming)],
                },
                .in_use = true,
            };

            node_start.edges[@enumToInt(Direction.Outgoing)] = idx;
            node_end.edges[@enumToInt(Direction.Incoming)] = idx;

            return idx;
        }

        pub fn removeEdge(self: *Self, idx: EdgeIndex) void {
            var dead_edge = &self.edges.items[idx];

            self.removeEdgeFromNode(dead_edge.start_node, idx, .Outgoing);
            self.removeEdgeFromNode(dead_edge.start_node, idx, .Incoming);
            self.removeEdgeFromNode(dead_edge.end_node, idx, .Outgoing);
            self.removeEdgeFromNode(dead_edge.end_node, idx, .Incoming);

            dead_edge.next[0] = self.next_edge;
            dead_edge.in_use = false;
            self.next_edge = idx;
        }

        pub fn edgesDirected(
            self: Self,
            idx: NodeIndex,
            direction: Direction,
        ) EdgeIterator {
            const node = self.nodes.items[idx];
            const start_idx = node.edges[@enumToInt(direction)];
            return EdgeIterator{
                .graph = &self,
                .curr_idx = start_idx,
                .direction = direction,
            };
        }

        pub fn toposort(
            self: Self,
            allocator: *Allocator,
            workspace_allocator: *Allocator,
        ) ![]NodeIndex {
            if (self.nodes.items.len == 0) {
                return try allocator.alloc(NodeIndex, 0);
            }

            const node_ct = self.nodes.items.len;

            var ret: ArrayList(NodeIndex) = ArrayList(NodeIndex).init(allocator);
            errdefer ret.deinit();

            var marked = try workspace_allocator.alloc(bool, node_ct);
            defer workspace_allocator.free(marked);
            var visited = try workspace_allocator.alloc(bool, node_ct);
            defer workspace_allocator.free(visited);

            {
                var i: usize = 0;
                while (i < node_ct) : (i += 1) {
                    marked[i] = false;
                    visited[i] = false;
                }
            }

            var stack = try ArrayList(NodeIndex).initCapacity(workspace_allocator, node_ct);
            defer stack.deinit();

            var check_idx: usize = 0;
            while (check_idx < node_ct) : (check_idx += 1) {
                if (!self.nodes.items[check_idx].in_use) {
                    continue;
                }

                if (visited[check_idx]) {
                    continue;
                }

                try stack.append(check_idx);
                while (stack.items.len > 0) {
                    const idx = stack.items[stack.items.len - 1];
                    marked[idx] = true;

                    const node = self.nodes.items[idx];
                    var children_to_check = false;
                    if (node.edges[@enumToInt(Direction.Outgoing)]) |_| {
                        var edge_iter = self.edgesDirected(idx, .Outgoing);
                        while (edge_iter.next()) |ref| {
                            const child_idx = ref.edge.end_node;
                            if (marked[child_idx]) {
                                if (!visited[child_idx]) {
                                    return error.CycleDetected;
                                }
                            } else {
                                try stack.append(ref.edge.end_node);
                                children_to_check = true;
                            }
                        }
                    }

                    if (!children_to_check) {
                        _ = stack.pop();
                        try ret.append(idx);
                        visited[idx] = true;
                    }
                }
            }

            std.mem.reverse(NodeIndex, ret.items);

            return ret.toOwnedSlice();
        }
    };
}

// TODO write tests

const testing = std.testing;
const expect = testing.expect;

test "graph" {
    const alloc = testing.allocator;

    var g = Graph(u8, u8).init(alloc);
    defer g.deinit();

    const a = try g.addNode('a');
    const b = try g.addNode('b');
    const c = try g.addNode('c');
    const d = try g.addNode('d');
    const e = try g.addNode('e');

    const e1 = try g.addEdge(b, a, 1);
    const e2 = try g.addEdge(a, d, 2);
    const e3 = try g.addEdge(c, e, 3);
    const e4 = try g.addEdge(d, e, 4);
    // const e5 = try g.addEdge(e, a, 5);

    // g.removeEdge(e4);

    var edges = g.edgesDirected(a, .Outgoing);
    while (edges.next()) |ref| {
        std.log.warn("\n{}\n", .{ref.edge});
    }

    const sort = try g.toposort(alloc, alloc);
    defer alloc.free(sort);
    for (sort) |idx| {
        const node = g.nodes.items[idx];
        std.log.warn("{c}\n", .{node.weight});
    }
}
