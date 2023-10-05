const $items = document.getElementById('items');

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
    $item.id = `changeset-` + getItemId($item);
    const $checkbox = document.createElement('input');
    $checkbox.type = 'checkbox';
    const changesCount = getItemChangesCount($item);
    let size = 0;
    if (changesCount > 0) {
        const cappedChangesCount = Math.min(9999, changesCount);
        size = 1 + Math.floor(Math.log10(cappedChangesCount));
    }
    $checkbox.dataset.size = size;
    $item.prepend($checkbox, ` `);
}
$items.onclick = ev => {
    const $clickedCheckbox = ev.target;
    if (!($clickedCheckbox instanceof HTMLInputElement)) return;
    if ($clickedCheckbox.type != 'checkbox') return;
    let $item = $clickedCheckbox.closest('li');
    if ($item.classList.contains('separator')) {
        while ($item = $item.nextElementSibling) {
            if ($item.classList.contains('separator')) break;
            const $checkbox = getItemCheckbox($item);
            setCheckboxChecked($checkbox, $clickedCheckbox.checked);
        }
        $lastClickedCheckbox = undefined;
    } else if ($item.classList.contains('changeset')) {
        setCheckboxStatus($clickedCheckbox);
        if (ev.shiftKey && $lastClickedCheckbox) {
            setCheckboxChecked($lastClickedCheckbox, $clickedCheckbox.checked);
            for ($checkbox of getCheckboxesBetweenCheckboxes($lastClickedCheckbox, $clickedCheckbox)) {
                setCheckboxChecked($checkbox, $clickedCheckbox.checked);
            }
        }
        $lastClickedCheckbox = $clickedCheckbox;
    }
    updateSelection();
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
    const $viewSelect = document.createElement('select');
    $viewSelect.append(
        new Option("Expanded view", 'expanded'),
        new Option("Compact view", 'compact')
    );
    $viewSelect.oninput = () => {
        $items.classList.toggle('compact', $viewSelect.value == 'compact');
    };
    $tool.append(` `, $viewSelect);
    $header.append($tool);
}
{
    const $tool = document.createElement('span');
    $tool.classList.add('tool');
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
            $separator.remove();
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
            $item.before($separator);
        }
        addCount();
        updateSelection();

        function addCount() {
            if (!$checkbox) return;
            $checkbox.after(`×${count}`);
            count = 0;
        }
    };
    $tool.append(` `, $separatorSelect);
    $header.append($tool);
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
    $footer.append(` `,$tool);
}
{
    const $tool = makeRcTool(`Open with RC`, id => {
        const changesetUrl = weburl + `changeset/` + encodeURIComponent(id);
        return `import?url=` + encodeURIComponent(changesetUrl);
    });
    $footer.append(` `,$tool);
}
{
    const $tool = makeRcTool(`Revert with RC`, id => {
        return `revert_changeset?id=` + encodeURIComponent(id);
    });
    $footer.append(` `,$tool);
}
document.body.append($footer);

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
        const id = getItemId($item);
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

function getItemId($item) {
    const $a = $item.querySelector('a');
    if (!$a) return;
    return $a.textContent;
}
function getItemTime($item) {
    const $time = $item.querySelector('time');
    if (!$time) return;
    return $time.dateTime;
}
function getItemChangesCount($item) {
    const $n = $item.querySelector('.changes .count');
    if (!$n) return;
    return Number($n.textContent);
}

function getItemCheckbox($item) {
    return $item.querySelector('input[type=checkbox]');
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
