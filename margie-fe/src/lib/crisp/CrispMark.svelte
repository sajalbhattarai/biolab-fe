<script lang="ts">
	/** MARGIE's mark: the app icon (static/margie-icon.png). */
	let { size = 24 }: { size?: number } = $props();
</script>

<img class="cr-mark" src="/margie-icon.png" width={size} height={size} alt="" aria-hidden="true" />

<style>
	.cr-mark {
		flex-shrink: 0;
		display: block;
		border-radius: 22%;
	}
</style>
