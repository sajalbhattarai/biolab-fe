/** The element id a collapsible section's body gets, for aria-controls. */
export const foldDomId = (id: string) => 'fold-' + id.replace(/[^\w-]/g, '-');
