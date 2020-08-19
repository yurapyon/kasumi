const std = @import("std");
const ArrayList = std.ArrayList;

const NodeIndex = usize;
const EdgeIndex = usize;

const EdgeMax = std.math.maxInt(EdgeIndex);

fn Node(comptime NodeWeight: type) type {
    return struct {
        weight: NodeWeight,
        next_outgoing: EdgeIndex,
        next_incoming: EdgeIndex,
    };
}

fn Edge(comptime EdgeWeight: type) type {
    return struct {
        weight: EdgeWeight,

        start_node: NodeIndex,
        end_node: NodeIndex,

        next_outgoing: EdgeIndex,
        next_incoming: EdgeIndex,
    };
}

fn EdgeIterator(comptime NodeWeight: type, comptime EdgeWeight: type) type {
    return struct {
        const Self = @This();

        graph: *Graph(NodeWeight, EdgeWeight),
        curr_idx: EdgeIndex,
        do_outgoing: bool,

        fn init(graph: *Graph(NodeWeight, EdgeWeight), start_idx: EdgeIndex, do_outgoing: bool) Self {
            return Self{
                .graph = graph,
                .curr_idx = start_idx,
                .do_outgoing = do_outgoing,
            };
        }

        pub fn next(self: *Self) ?*Edge(EdgeWeight) {
            if (self.curr_idx == EdgeMax) {
                return null;
            } else {
                const edge = &self.graph.edges.items[self.curr_idx];
                const next_idx = if (self.do_outgoing) edge.next_outgoing else edge.next_incoming;
                self.curr_idx = next_idx;
                return edge;
            }
        }
    };
}

const GraphError = error{
    NodeIndexOutOfBounds,
    EdgeIndexOutOfBounds,
};

pub fn Graph(comptime NodeWeight: type, comptime EdgeWeight: type) type {
    return struct {
        const Self = @This();
        const NodeList = ArrayList(Node(NodeWeight));
        const EdgeList = ArrayList(Edge(EdgeWeight));

        allocator: *std.mem.Allocator,
        nodes: NodeList,
        edges: EdgeList,

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .nodes = NodeList.init(allocator),
                .edges = EdgeList.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();
            self.edges.deinit();
        }

        pub fn add_node(self: *Self, weight: NodeWeight) !NodeIndex {
            const new_id = self.nodes.items.len;
            try self.nodes.append(.{
                .weight = weight,
                .next_outgoing = std.math.maxInt(EdgeIndex),
                .next_incoming = std.math.maxInt(EdgeIndex),
            });
            return new_id;
        }

        pub fn add_edge(
            self: *Self,
            start_idx: NodeIndex,
            end_idx: NodeIndex,
            weight: EdgeWeight,
        ) !EdgeIndex {
            if (start_idx >= self.nodes.items.len or
                end_idx >= self.nodes.items.len)
            {
                return error.NodeIndexOutOfBounds;
            }

            const new_id = self.edges.items.len;
            var node_a = &self.nodes.items[start_idx];
            var node_b = &self.nodes.items[end_idx];

            var edge = .{
                .weight = weight,
                .start_node = start_idx,
                .end_node = end_idx,
                .next_outgoing = node_a.next_outgoing,
                .next_incoming = node_b.next_incoming,
            };

            node_a.next_outgoing = new_id;
            node_b.next_incoming = new_id;

            try self.edges.append(edge);
            return new_id;
        }

        pub fn edges_directed(
            self: *Self,
            node_idx: NodeIndex,
            do_outgoing: bool,
        ) EdgeIterator(NodeWeight, EdgeWeight) {
            const node = self.nodes.items[node_idx];
            const start_idx = if (do_outgoing) node.next_outgoing else node.next_incoming;
            return EdgeIterator(NodeWeight, EdgeWeight).init(self, start_idx, do_outgoing);
        }
    };
}
