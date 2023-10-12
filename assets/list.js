const $items = document.getElementById('items');

const $criticalChangesetControls = [];

const numberGroupWidths = new Map();
for (const $number of $items.querySelectorAll('[data-number]')) {
    const group = $number.dataset.number;
    numberGroupWidths.set(group, Math.max(numberGroupWidths.get(group) ?? 0, $number.textContent.length));
}
{
    const $style = document.createElement('style');
    const changesetsCount = $items.querySelectorAll('li.changeset').length;
    $style.textContent = (
        `:root { --changesets-count-width: ${String(changesetsCount).length}ch }` +
        [...numberGroupWidths].map(([group, width]) => `[data-number="${group}"] { min-width: ${width}ch }\n`).join('')
    );
    document.head.append($style);
}

const separatorSizes = [
    // 1234567890123456789
    // 2020-01-02T03:04:05Z
    ['minute', 16],
    ['hour', 13],
    ['day', 10],
    ['month', 7],
    ['year', 4]
];
const $separatorSelect = document.createElement('select');
$separatorSelect.append(
    new Option(`No split`, 0),
    ...separatorSizes.map(([text, size]) => new Option(`Split by ${text}`, size))
);
$separatorSelect.oninput = () => {
    for (const $separator of $items.querySelectorAll('li.separator')) {
        removeElementWithWhitespaceAround($separator);
    }
    const size = Number($separatorSelect.value);
    if (!size) return;
    let count = 0;
    let lastTime;
    let $checkbox;
    for (const $item of $items.querySelectorAll('li.changeset')) {
        count++;
        const uncutTime = getItemTime($item);
        if (!uncutTime) continue;
        const time = uncutTime.slice(0, size);
        if (lastTime == time) continue;
        lastTime = time;
        count--;
        addCount();
        count++;

        let label = time.replace('T', ' ');
        if (label.length == 13) label += ':--';

        const $selector = document.createElement('span');
        $selector.classList.add('selector');
        $checkbox = document.createElement('input');
        $checkbox.type = 'checkbox';
        $checkbox.title = `select changesets in ${label}`;
        $selector.append($checkbox);

        const $time = document.createElement('time');
        $time.append(label);
        const $separator = document.createElement('li');
        $separator.classList.add('separator');
        $separator.append($selector,` `,$time);
        $item.before($separator,`\n`);
    }
    addCount();
    updateSelection();

    function addCount() {
        if (!$checkbox) return;
        $checkbox.after(`×${count}`);
        count = 0;
    }
};

const changesWidgetData = [];
if ($items.querySelector('.changes-operation')) {
    changesWidgetData.push(['.changes-operation', `create/modify/delete changes`, `📝(c/m/d)`]);
}
if ($items.querySelector('.changes-element')) {
    changesWidgetData.push(['.changes-element', `node/way/relation changes`, `📝(n/w/r)`]);
}
if ($items.querySelector('.changes-operation-x-element')) {
    changesWidgetData.push(['.changes-operation-x-element', `create/modify/delete × node/way/relation changes`, `📝(c/m/d × n/w/r)`]);
}
{
    changesWidgetData.unshift(['.changes-total', `changes`, `📝` + (changesWidgetData.length ? `(*)` : ``)]);
}
if ($items.querySelector('.changes-target')) {
    changesWidgetData.push(['.changes-target', `target changes`, `🎯`]);
}
const widgetData = [
    ['time', `time`, `📅`],
    ...changesWidgetData,
    ['.area', `area`, `📐`],
    ['.comment', `comment`, `💬`],
];

const $widgetVisibilityControls = [false, true].map(isCompact => widgetData.map(([selector]) => {
    const $checkbox = document.createElement('input');
    $checkbox.type = 'checkbox';
    $checkbox.checked = !isCompact;
    $checkbox.onclick = () => {
        let compactnessSelector = `.compact`;
        if (!isCompact) compactnessSelector = `:not(${compactnessSelector})`;
        for (const $widget of $items.querySelectorAll(`li.changeset${compactnessSelector} ${selector}`)) {
            $widget.hidden = !$checkbox.checked;
        }
    };
    $criticalChangesetControls.push($checkbox);
    return $checkbox;
}));

const $globalDisclosureButtons = [false, true].map(isCompact => {
    const $button = document.createElement('button');
    $button.textContent = !isCompact ? `+` : `−`;
    $button.title = !isCompact ? `expand all` : `collapse all`;
    $button.onclick = () => {
        for (const $control of $criticalChangesetControls) {
            $control.disabled = true;
        }
        requestAnimationFrame(time => walker($items.firstElementChild, time));
    };
    $criticalChangesetControls.push($button);
    return $button;

    function walker($item, time) {
        for (let i = 0;; i++, $item = $item.nextElementSibling) {
            if (i >= 10 && performance.now() - time >= 20) break;
            if (!$item) break;
            if (!$item.classList.contains('changeset')) continue;
            $item.classList.toggle('compact', isCompact);
            updateItemDisclosure($item);
        }
        if ($item) {
            requestAnimationFrame(time => walker($item, time));
        } else {
            for (const $control of $criticalChangesetControls) {
                $control.disabled = false;
            }
        }
    }
});

let $lastClickedCheckbox;
const $selectAllCheckbox = document.createElement('input');
$selectAllCheckbox.type = 'checkbox';
$selectAllCheckbox.title = `select all changesets`;
$selectAllCheckbox.onclick = () => {
    for (const $checkbox of $items.querySelectorAll('li.changeset input[type=checkbox]')) {
        setCheckboxChecked($checkbox, $selectAllCheckbox.checked);
    }
    updateSelection();
    $lastClickedCheckbox = undefined;
};

const $selectedCountOutput = document.createElement('output');
$selectedCountOutput.title = `number of selected changesets`;
$selectedCountOutput.textContent = 0;

for (const $item of $items.querySelectorAll('li.changeset')) {
    const $a = $item.querySelector('a');
    if ($a) {
        const maxIdLength = numberGroupWidths.get('id');
        const id = $a.textContent;
        $item.dataset.id = id;
        $item.id = `changeset-` + id;
        if (id.length < maxIdLength) {
            const $pad = document.createElement('span');
            $pad.classList.add('pad');
            $pad.textContent = '·'.repeat(maxIdLength - id.length);
            $a.prepend($pad);
        }
    }
    const $checkbox = document.createElement('input');
    $checkbox.type = 'checkbox';
    const changesCount = getItemChangesCount($item);
    let size = 0;
    if (changesCount > 0) {
        const cappedChangesCount = Math.min(9999, changesCount);
        size = 1 + Math.floor(Math.log10(cappedChangesCount));
    }
    $checkbox.dataset.size = size;
    const $disclosureButton = document.createElement('button');
    $disclosureButton.classList.add('disclosure');
    const $holder = document.createElement('span');
    $holder.classList.add('holder');
    const $controls = document.createElement('span');
    $controls.classList.add('controls');
    $controls.append($checkbox, ` `, $disclosureButton);
    $holder.append($controls, ` `, $item.firstElementChild);
    $item.prepend($holder);
    updateItemDisclosure($item);
}
$items.onclick = ev => {
    const $clicked = ev.target;
    if ($clicked instanceof HTMLInputElement && $clicked.type == 'checkbox') {
        let $item = $clicked.closest('li');
        if ($item.classList.contains('separator')) {
            while ($item = $item.nextElementSibling) {
                if ($item.classList.contains('separator')) break;
                const $checkbox = getItemCheckbox($item);
                setCheckboxChecked($checkbox, $clicked.checked);
            }
            $lastClickedCheckbox = undefined;
        } else if ($item.classList.contains('changeset')) {
            setCheckboxStatus($clicked);
            if (ev.shiftKey && $lastClickedCheckbox) {
                setCheckboxChecked($lastClickedCheckbox, $clicked.checked);
                for ($checkbox of getCheckboxesBetweenCheckboxes($lastClickedCheckbox, $clicked)) {
                    setCheckboxChecked($checkbox, $clicked.checked);
                }
            }
            $lastClickedCheckbox = $clicked;
        }
        updateSelection();
    } else if ($clicked instanceof HTMLButtonElement && $clicked.classList.contains('disclosure')) {
        const $item = $clicked.closest('li');
        $item.classList.toggle('compact');
        updateItemDisclosure($item);
    }
};

const $header = document.createElement('header');
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const count = $items.querySelectorAll('li.changeset').length;
    $tool.append($selectAllCheckbox, `×${count}`);
    $header.append($tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const $sortSelect = document.createElement('select');
    $sortSelect.append(
        ...['time', ...numberGroupWidths.keys()].map(k => new Option(`Sort by ${k}`, k))
    );
    $sortSelect.oninput = () => {
        $separatorSelect.value = 0;
        $separatorSelect.disabled = $sortSelect.value != 'time';
        const numberSelector = `[data-number="${$sortSelect.value}"]`;
        const $itemsToRemove = [];
        const $itemsToSort = [];
        for (const $item of $items.children) {
            if (!$item.classList.contains('changeset')) {
                $itemsToRemove.push($item);
                continue;
            }
            let sortKey;
            if ($sortSelect.value == 'time') {
                const $time = $item.querySelector('time');
                if (!$time) continue;
                sortKey = $time.dateTime;
            } else {
                const $number = $item.querySelector(numberSelector);
                if (!$number) continue;
                sortKey = Number($number.textContent);
            }
            $itemsToSort.push([sortKey, $item]);
        }
        for (const $item of $itemsToRemove) removeElementWithWhitespaceAround($item);
        $itemsToSort.sort(([a], [b]) => a > b);
        for (const [,$item] of $itemsToSort) $items.prepend($item,`\n`);
    };
    $criticalChangesetControls.push($sortSelect);
    $tool.append($sortSelect);
    $header.append($tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    $tool.append(` `, $separatorSelect);
    $header.append(` `, $tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const $select = document.createElement('select');
    $select.append(
        new Option(`Line breaks`, 'br'),
        new Option(`No line breaks`, 'nobr'),
    );
    $select.oninput = () => {
        $items.classList.toggle('without-line-breaks', $select.value == 'nobr');
    };
    $tool.append($select);
    $header.append(` `, $tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool', 'visibility');
    for (const [isCompact, $modeWidgetVisibilityControls] of $widgetVisibilityControls.entries()) {
        const $subtool = document.createElement('span');
        $subtool.classList.add('tool');
        $subtool.append($globalDisclosureButtons[isCompact]);
        for (const [i, $checkbox] of $modeWidgetVisibilityControls.entries()) {
            const [, name, icon] = widgetData[i];
            const $label = document.createElement('label');
            $label.append($checkbox, ` `, icon);
            $label.title = name;
            $subtool.append(` `, $label);
        }
        $tool.append(` `, $subtool);
    }
    $header.append(` `, $tool);
}
document.body.prepend($header);

const $footer = document.createElement('footer');
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const $dummyCheckbox = document.createElement('input');
    $dummyCheckbox.type = 'checkbox';
    $dummyCheckbox.checked = true;
    $dummyCheckbox.disabled = true;
    $tool.append($dummyCheckbox, `×`, $selectedCountOutput, ` ⇒`);
    $footer.append($tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');

    const $typeSelect = document.createElement('select');
    $typeSelect.append(
        new Option('URLs'),
        new Option('ids')
    );

    const $separatorInput = document.createElement('input');
    $separatorInput.type = 'text';
    $separatorInput.size = 3;
    $separatorInput.value = `\\n`;

    const $button = document.createElement('button');
    $button.append(`📋`);
    $button.onclick = () => {
        const separator=$separatorInput.value.replace(/\\(.)/g, (_, c) => {
            if (c=='n') return '\n';
            if (c=='t') return '\t';
            return c;
        });
        const text = getSelectedChangesetIds().map(id => {
            if ($typeSelect.value == 'URLs') {
                return weburl + `changeset/` + encodeURIComponent(id);
            } else {
                return id;
            }
        }).join(separator);
        navigator.clipboard.writeText(text);
    };

    const $separatorInputLabel = document.createElement('label');
    $separatorInputLabel.append(`separated by `, $separatorInput);
    $tool.append(
        `Copy `, $typeSelect, ` `,
        $separatorInputLabel, ` `,
        `to clipboard `, $button
    );
    $footer.append(` `, $tool);
}
{
    const $tool = makeRcTool(`Open with RC`, id => {
        const changesetUrl = weburl + `changeset/` + encodeURIComponent(id);
        return `import?url=` + encodeURIComponent(changesetUrl);
    });
    $footer.append(` `, $tool);
}
{
    const $tool = makeRcTool(`Revert with RC`, id => {
        return `revert_changeset?id=` + encodeURIComponent(id);
    });
    $footer.append(` `, $tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const $button = document.createElement('button');
    $button.append(`Clear statuses`);
    $button.onclick = () => {
        for (const $checkbox of $items.querySelectorAll('li.changeset input[type=checkbox]')) {
            setCheckboxStatus($checkbox);
        }
    };
    $tool.append($button);
    $footer.append(` `, $tool);
}
document.body.append($footer);

function updateItemDisclosure($item) {
    const isCompact = $item.classList.contains('compact');
    const $disclosureButton = getItemDisclosureButton($item);
    $disclosureButton.textContent = isCompact ? `+` : `−`;
    $disclosureButton.title = isCompact ? `expand` : `collapse`;
    for (const [i, $checkbox] of $widgetVisibilityControls[Number(isCompact)].entries()) {
        const [selector] = widgetData[i];
        const $widget = $item.querySelector(selector);
        if (!$widget) continue;
        $widget.hidden = !$checkbox.checked;
    }
}

function updateSelection() {
    let checkedTotalCount = 0;
    let uncheckedTotalCount = 0;
    let checkedGroupCount = 0;
    let uncheckedGroupCount = 0;
    let $groupCheckbox;
    for (const $item of $items.querySelectorAll('li')) {
        if ($item.classList.contains('separator')) {
            if ($groupCheckbox) {
                $groupCheckbox.checked = checkedGroupCount && !uncheckedGroupCount;
                $groupCheckbox.indeterminate = checkedGroupCount && uncheckedGroupCount;
            }
            checkedGroupCount = 0;
            uncheckedGroupCount = 0;
            $groupCheckbox = getItemCheckbox($item);
        } else if ($item.classList.contains('changeset')) {
            const $checkbox = getItemCheckbox($item);
            checkedTotalCount += $checkbox.checked;
            uncheckedTotalCount += !$checkbox.checked;
            checkedGroupCount += $checkbox.checked;
            uncheckedGroupCount += !$checkbox.checked;
        }
    }
    $selectedCountOutput.textContent = checkedTotalCount;
    $selectAllCheckbox.checked = checkedTotalCount && !uncheckedTotalCount;
    $selectAllCheckbox.indeterminate=checkedTotalCount && uncheckedTotalCount;
}

function getSelectedChangesetIds() {
    const ids = [];
    for (const $item of $items.querySelectorAll('li.changeset')) {
        const $checkbox = getItemCheckbox($item);
        if (!$checkbox.checked) continue;
        const id = $item.dataset.id;
        if (id == null) continue;
        ids.push(id);
    }
    return ids;
}

function *getCheckboxesBetweenCheckboxes($checkbox1, $checkbox2) {
    let inside = 0;
    for (const $checkbox of $items.querySelectorAll('li.changeset input[type=checkbox]')) {
        inside ^= ($checkbox == $checkbox1) ^ ($checkbox == $checkbox2);
        if (inside) yield $checkbox;
    }
}

function getItemTime($item) {
    const $time = $item.querySelector('time');
    if (!$time) return;
    return $time.dateTime;
}
function getItemChangesCount($item) {
    const $n = $item.querySelector('.changes .number.total');
    if (!$n) return;
    return Number($n.textContent);
}

function getItemCheckbox($item) {
    return $item.querySelector('input[type=checkbox]');
}
function getItemDisclosureButton($item) {
    return $item.querySelector('button.disclosure');
}

function setCheckboxChecked($checkbox, checked) {
    $checkbox.checked = checked;
    setCheckboxStatus($checkbox);
}
function setCheckboxStatus($checkbox, status) {
    if (status == null) {
        delete $checkbox.dataset.status;
        $checkbox.removeAttribute('title');
    } else {
        $checkbox.dataset.status = status;
        $checkbox.title = status;
    }
}

function makeRcTool(name, getRcPath) {
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
    const $button = document.createElement('button');
    $button.append(name);
    $button.onclick = () => runRcBatch($button, getRcPath);
    $tool.append($button);
    return $tool;
}

async function runRcBatch($button, getRcPath) {
    let $checkbox;
    try {
        $button.disabled = true;
        for (const id of getSelectedChangesetIds()) {
            const $item = document.getElementById(`changeset-` + id);
            if ($item) $checkbox = getItemCheckbox($item);
            if ($checkbox) setCheckboxStatus($checkbox, 'running');
            await openRcPath($button, getRcPath(id));
            if ($checkbox) setCheckboxStatus($checkbox, 'succeeded');
        }
    } catch {
        if ($checkbox) setCheckboxStatus($checkbox, 'failed');
    } finally {
        $button.disabled = false;
    }
}

async function openRcPath($button, rcPath) {
    const rcUrl = `http://127.0.0.1:8111/` + rcPath;
    try {
        const response = await fetch(rcUrl);
        if (!response.ok) throw new Error();
        clearError();
    } catch {
        setError();
        throw new Error();
    }
    function setError() {
        $button.classList.add('error');
        $button.title = `Remote control command failed. Make sure you have an editor open and remote control enabled.`;
    }
    function clearError() {
        $button.classList.remove('error');
        $button.title = '';
    }
}

function removeElementWithWhitespaceAround($e) {
    if (isWhitespaceNode($e.previousSibling)) {
        $e.previousSibling.remove()
    } else if (isWhitespaceNode($e.nextSibling)) {
        $e.nextSibling.remove()
    }
    $e.remove()
}
function isWhitespaceNode($s) {
    return Boolean($s?.nodeType==document.TEXT_NODE && $s.textContent.match(/^\s+$/));
}
