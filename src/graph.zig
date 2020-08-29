const std = @import("std");
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

/// data can be accessed by going like graph.nodes.items[some_idx]
pub fn Graph(comptime N: type, comptime E: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            weight: N,

            next: ?NodeIndex,

            edges: [2]?EdgeIndex,
        };

        const Edge = struct {
            weight: E,

            start_node: NodeIndex,
            end_node: NodeIndex,

            next: [2]?EdgeIndex,
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
                        var find_edge = self.edges.items[_find_idx_];

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

            self.nodes.items[idx] = Node{
                .weight = weight,
                .next = null,
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

            self.nodes.items[idx].next = self.next_node;
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

            self.edges.items[idx] = Edge{
                .weight = weight,
                .start_node = start_idx,
                .end_node = end_idx,
                .next = .{
                    node_start.edges[@enumToInt(Direction.Outgoing)],
                    node_end.edges[@enumToInt(Direction.Incoming)],
                },
            };

            node_start.edges[@enumToInt(Direction.Outgoing)] = idx;
            node_end.edges[@enumToInt(Direction.Incoming)] = idx;

            return idx;
        }

        pub fn removeEdge(self: *Self, idx: EdgeIndex) void {
            var edge = &self.edges.items[idx];

            self.removeEdgeFromNode(edge.start_node, idx, .Outgoing);
            self.removeEdgeFromNode(edge.start_node, idx, .Incoming);
            self.removeEdgeFromNode(edge.end_node, idx, .Outgoing);
            self.removeEdgeFromNode(edge.end_node, idx, .Incoming);

            edge.next[0] = self.next_edge;
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
    };
}

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

    const e1 = try g.addEdge(a, b, 1);
    const e2 = try g.addEdge(b, c, 2);
    const e3 = try g.addEdge(a, d, 3);
    const e4 = try g.addEdge(c, d, 4);
    const e5 = try g.addEdge(d, e, 5);

    g.removeEdge(e4);

    var edges = g.edgesDirected(a, .Outgoing);
    while (edges.next()) |ref| {
        std.log.warn("\n{}\n", .{ref.edge});
    }
}
