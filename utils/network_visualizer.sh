#!/bin/bash

#############################################
# Network Visualization Helper
#############################################

generate_graphviz() {
    local json_file=$1
    local output_dot="${json_file%.json}.dot"
    
    echo "Generating GraphViz DOT file..."
    
    cat > "${output_dot}" << 'EOF'
digraph RedditNetwork {
    graph [bgcolor=white, rankdir=LR];
    node [shape=circle, style=filled, fillcolor=lightblue];
    edge [color=gray];
    
EOF
    
    # Add nodes
    jq -r '.graph_data.nodes[] | "    \"\(.id)\" [label=\"\(.label)\", fontsize=\(.degree+8)];"' "${json_file}" >> "${output_dot}"
    
    echo "" >> "${output_dot}"
    
    # Add edges
    jq -r '.graph_data.edges[] | "    \"\(.source)\" -> \"\(.target)\" [weight=\(.weight)];"' "${json_file}" >> "${output_dot}"
    
    echo "}" >> "${output_dot}"
    
    echo "GraphViz file created: ${output_dot}"
    echo "Render with: dot -Tpng ${output_dot} -o network.png"
}
