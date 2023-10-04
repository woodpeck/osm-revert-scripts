const $changesets = document.getElementById('changesets');
const $viewSelect = document.createElement('select');
$viewSelect.append(
    new Option("Expanded view", 'expanded'),
    new Option("Compact view", 'compact')
);
$viewSelect.oninput = () => {
    $changesets.classList.toggle('compact', $viewSelect.value == 'compact');
};
const $header = document.createElement('header');
$header.append($viewSelect);
document.body.prepend($header);
