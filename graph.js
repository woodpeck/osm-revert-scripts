let minUid = +Infinity;
let maxUid = -Infinity;
for (const node of gData.nodes) {
    const uid = node.uid;
    if (!uid) continue;
    if (uid < minUid) minUid = uid;
    if (uid > maxUid) maxUid = uid;
}

const Graph = ForceGraph()
(document.getElementById('graph'))
    .graphData(gData)
    .linkWidth(({weight}) => 32*Math.log(weight)/Math.log(10000))
    .linkDirectionalArrowLength(6)
    .nodeLabel((node) => {
        const popup = document.createElement('span');
        const user = document.createElement('strong');
        user.append(node.user);
        popup.append(`by `, user, ` (#${node.uid})`);
        return popup.innerHTML;
    })
    .nodeCanvasObject((node, ctx, globalScale) => {
        // const labels = [node.id, node.user, node.uid];
        const labels = [node.id];
        const fontSize = 12/globalScale;
        ctx.font = `${fontSize}px Sans-Serif`;
        const textWidth = Math.max(...labels.map(label => ctx.measureText(label).width));
        const gap = fontSize * 0.1;
        const nodeWidth = textWidth + 2 * gap;
        const nodeHeight = labels.length * fontSize + (labels.length + 1) * gap;

        if (node.selected) {
            ctx.fillStyle = 'rgba(255, 255, 0, 0.8)';
        } else {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
        }
        ctx.fillRect(node.x - nodeWidth / 2, node.y - nodeHeight / 2, nodeWidth, nodeHeight);

        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        if (node.uid && maxUid > minUid) {
            const heat = (node.uid - minUid) / (maxUid - minUid);
            ctx.fillStyle = `rgb(${100 * heat}%, 20%, ${100 * (1 - heat)}%)`;
        } else {
            ctx.fillStyle = `rgb(100%, 20%, 0%)`;
        }
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
