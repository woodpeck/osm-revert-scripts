const Graph = ForceGraph()
(document.getElementById('graph'))
    .graphData(gData)
    .linkWidth(({weight}) => 32*Math.log(weight)/Math.log(10000))
    .linkDirectionalArrowLength(6)
    .nodeCanvasObject((node, ctx, globalScale) => {
        const labels = [node.id, node.user, node.uid];
        const fontSize = 12/globalScale;
        ctx.font = `${fontSize}px Sans-Serif`;
        const textWidth = Math.max(...labels.map(label => ctx.measureText(label).width));
        const gap = fontSize * 0.1;
        const nodeWidth = textWidth + 2 * gap;
        const nodeHeight = 3 * fontSize + 4 * gap;

        if (node.selected) {
            ctx.fillStyle = 'rgba(255, 255, 0, 0.8)';
        } else {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
        }
        ctx.fillRect(node.x - nodeWidth / 2, node.y - nodeHeight / 2, nodeWidth, nodeHeight);

        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = '#3183ba';
        for (let i = 0; i < labels.length; i++) {
            const label = labels[i];
            const iOffset = i - (labels.length - 1) / 2;
            const yOffset = iOffset * (fontSize + gap);
            ctx.fillText(label, node.x, node.y + yOffset);
        }

        node.__bckgDimensions = [nodeWidth, nodeHeight]; // to re-use in nodePointerAreaPaint
    })
    .nodePointerAreaPaint((node, color, ctx) => {
        ctx.fillStyle = color;
        const bckgDimensions = node.__bckgDimensions;
        bckgDimensions && ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);
    })
    .onNodeClick(node => {
        window.open("https://www.openstreetmap.org/changeset/" + node.id);
    });
