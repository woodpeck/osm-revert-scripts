const $changesets = document.getElementById('changesets');

const $selectAllCheckbox = document.createElement('input');
$selectAllCheckbox.type = 'checkbox';
$selectAllCheckbox.title = `select all changesets`;
$selectAllCheckbox.onclick = () => {
    for (const $checkbox of $changesets.querySelectorAll('li.item input[type=checkbox]')) {
        $checkbox.checked = $selectAllCheckbox.checked;
    }
    updateSelection();
};

const $selectedCountOutput = document.createElement('output');
$selectedCountOutput.textContent = 0;

const $viewSelect = document.createElement('select');
$viewSelect.append(
    new Option("Expanded view", 'expanded'),
    new Option("Compact view", 'compact')
);
$viewSelect.oninput = () => {
    $changesets.classList.toggle('compact', $viewSelect.value == 'compact');
};

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
    for (const $separator of $changesets.querySelectorAll('li.separator')) {
        $separator.remove();
    }
    const size = Number($separatorSelect.value);
    if (!size) return;
    let lastTime;
    for (const $item of $changesets.querySelectorAll('li.item')) {
        if (!($item instanceof HTMLElement)) continue;
        const uncutTime = getItemTime($item);
        if (!uncutTime) continue;
        const time = uncutTime.slice(0, size);
        if (lastTime == time) continue;
        lastTime = time;
        let label = time.replace('T', ' ');
        if (label.length == 13) label += ':**';
        const $time = document.createElement('time');
        $time.append(label);
        const $separator = document.createElement('li');
        $separator.classList.add('separator');
        $separator.append($time);
        $item.before($separator);
    }
};

for (const $item of $changesets.querySelectorAll('li.item')) {
    if (!($item instanceof HTMLElement)) continue;
    const $itemCheckbox = document.createElement('input');
    $itemCheckbox.type = 'checkbox';
    $item.prepend($itemCheckbox, ` `);
}
$changesets.onclick = ev => {
    const $clickedCheckbox = ev.target;
    if (!($clickedCheckbox instanceof HTMLInputElement)) return;
    if ($clickedCheckbox.type != 'checkbox') return;
    updateSelection();
};

const $header = document.createElement('header');
$header.append($selectAllCheckbox,` `,$viewSelect, ` `, $separatorSelect);
document.body.prepend($header);

const $footer = document.createElement('footer');
{
    const $tool = document.createElement('span');
    $tool.append(`Selected `, $selectedCountOutput, ` changesets; do with them:`);
    $footer.append($tool);
}
{
    const $tool = document.createElement('span');

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
                return `${weburl}changeset/${id}`;
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
document.body.append($footer);

function updateSelection() {
    let countChecked = 0;
    let countUnchecked = 0;
    for (const $checkbox of $changesets.querySelectorAll('li.item input[type=checkbox]')) {
        if (!($checkbox instanceof HTMLInputElement)) continue;
        countChecked += $checkbox.checked;
        countUnchecked += !$checkbox.checked;
    }
    $selectedCountOutput.textContent = countChecked;
    $selectAllCheckbox.checked = countChecked && !countUnchecked;
    $selectAllCheckbox.indeterminate=countChecked && countUnchecked;
}

function getSelectedChangesetIds() {
    const ids = [];
    for (const $item of $changesets.querySelectorAll('li.item')) {
        if (!($item instanceof HTMLElement)) continue;
        const $checkbox = getItemCheckbox($item);
        if (!$checkbox.checked) continue;
        const id = getItemId($item);
        if (id == null) continue;
        ids.push(id);
    }
    return ids;
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

function getItemCheckbox($item) {
    return $item.querySelector('input[type=checkbox]');
}
