<script lang="ts">
	let {
		checked,
		onchange,
		label,
		disabled = false
	}: { checked: boolean; onchange: (on: boolean) => void; label: string; disabled?: boolean } = $props();
</script>

<button type="button" role="switch" class="mg-switch" aria-checked={checked} aria-label={label} {disabled} onclick={() => onchange(!checked)}></button>
