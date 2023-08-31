let minUid = +Infinity;
let maxUid = -Infinity;
for (const node of gData.nodes) {
    const uid = node.uid;
    if (!uid) continue;
    if (uid < minUid) minUid = uid;
    if (uid > maxUid) maxUid = uid;
}

const myGraph = ForceGraph()
(document.getElementById('graph'))
    .graphData(gData)
    .linkWidth(({weight}) => 32*Math.log(weight)/Math.log(10000))
    .linkDirectionalArrowLength(6)
    .nodeLabel((node) => {
        const popup = document.createElement('span');
        const changeset = document.createElement('strong');
        const user = document.createElement('strong');
        changeset.append(`#`, node.id);
        user.append(node.user);
        popup.append(
            `changeset `, changeset, document.createElement('br'),
            `by `, user, document.createElement('br'),
            `with uid #${node.uid}`
        );
        if (node.comment) {
            const comment = document.createElement('small');
            comment.append(node.comment);
            popup.append(
                document.createElement('br'),
                comment
            );
        }
        return popup.innerHTML;
    }).onNodeClick(node => {
        window.open("https://www.openstreetmap.org/changeset/" + node.id);
    });

if (showCids || showUsers || showUids) {
    myGraph.nodeCanvasObject((node, ctx, globalScale) => {
        const labels = [];
        if (showCids) labels.push(node.id);
        if (showUsers) labels.push(node.user);
        if (showUids) labels.push(node.uid);
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
        ctx.fillStyle = getNodeColor(node);
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
    });
} else {
    const nodeRadius = 8;
    myGraph
        .nodeRelSize(nodeRadius)
        .nodeCanvasObjectMode(node => node.selected ? 'before' : undefined)
        .nodeColor(getNodeColor)
        .nodeCanvasObject((node, ctx) => {
            ctx.beginPath();
            ctx.arc(node.x, node.y, nodeRadius * 1.4, 0, 2 * Math.PI, false);
            ctx.fillStyle = 'rgba(255, 255, 0, 0.8)';
            ctx.fill();
        });
}

function getNodeColor(node) {
    if (node.uid && maxUid > minUid) {
        const heat = (node.uid - minUid) / (maxUid - minUid);
        return `rgb(${100 * heat}%, 20%, ${100 * (1 - heat)}%)`;
    } else {
        return `rgb(100%, 20%, 0%)`;
    }
}
