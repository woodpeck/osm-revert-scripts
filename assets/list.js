const $changesets = document.getElementById('changesets');

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
    $item.prepend($itemCheckbox,` `);
}
$changesets.onclick = ev => {
    const $clickedCheckbox = ev.target;
    if (!($clickedCheckbox instanceof HTMLInputElement)) return;
    if ($clickedCheckbox.type != 'checkbox') return;
    let count = 0;
    for (const $checkbox of $changesets.querySelectorAll('li.item input[type=checkbox]')) {
        if (!($checkbox instanceof HTMLInputElement)) continue;
        count += $checkbox.checked;
    }
    $selectedCountOutput.textContent = count;
};

const $header = document.createElement('header');
$header.append($viewSelect, ` `, $separatorSelect);
document.body.prepend($header);

const $footer = document.createElement('footer');
$footer.append(`Selected `, $selectedCountOutput, ` changesets`);
document.body.append($footer);

function getItemTime($item) {
    const $time = $item.querySelector('time');
    if (!$time) return;
    return $time.dateTime;
}
