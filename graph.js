const Graph = ForceGraph()
(document.getElementById('graph'))
    .graphData(gData)
    .linkWidth(({weight}) => 32*Math.log(weight)/Math.log(10000))
    .linkDirectionalArrowLength(6);
