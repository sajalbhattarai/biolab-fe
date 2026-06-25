<script lang="ts">
	import { onMount } from 'svelte';

	interface Props {
		param: string;
		type?: 'string' | 'int' | 'path' | 'number';
		description: string;
		default?: any;
		required?: boolean;
		compact?: boolean;
		value: any;
		onchange: (value: any) => void;
	}

	let {
		param,
		type = 'string',
		description,
		default: defaultValue = null,
		required = false,
		compact = false,
		value,
		onchange
	}: Props = $props();

	// Extract display name from param (e.g., "prodigal.threads" → "threads")
	let displayName = $derived(param.split('.').pop() || param);
	let isDefault = $derived(value === null || value === undefined || value === '');
	let displayValue = $derived(isDefault ? (defaultValue ?? '') : value);

	function handleInput(event: Event) {
		const target = event.target as HTMLInputElement;
		let newValue: any = target.value;

		// Convert to appropriate type
		if (type === 'int' || type === 'number') {
			newValue = newValue === '' ? null : parseInt(newValue, 10);
		}

		value = newValue;
		onchange(newValue);
	}
</script>

<div class="config-field {compact ? 'config-field-compact mb-2' : 'mb-4'}">
	<div class="flex-1 {compact ? 'mb-1' : 'mb-2'}">
		<span class="font-medium">
			{displayName}
			{#if required}
				<span class="text-error-500">*</span>
			{/if}
		</span>
		<p class="text-xs text-surface-600 dark:text-surface-400 mt-1">{description}</p>
		{#if !isDefault && defaultValue !== null}
			<p class="text-xs text-primary-600 dark:text-primary-400 mt-1">
				Default: {defaultValue}
			</p>
		{/if}
	</div>

	<div>
		{#if type === 'int' || type === 'number'}
			<input
				type="number"
				class="input"
				placeholder={defaultValue !== null ? String(defaultValue) : ''}
				value={displayValue}
				oninput={handleInput}
				required={required}
				aria-label={displayName}
			/>
		{:else}
			<input
				type="text"
				class="input"
				placeholder={defaultValue !== null ? String(defaultValue) : ''}
				value={displayValue}
				oninput={handleInput}
				required={required}
				aria-label={displayName}
			/>
		{/if}
	</div>
</div>

<style>
	.config-field {
		border-left: 3px solid rgb(var(--color-primary-500) / 0.3);
		padding-left: 0.75rem;
	}

	.config-field-compact {
		padding-left: 0.5rem;
	}
</style>
