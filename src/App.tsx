
async function saveLocation(e: FormEvent<HTMLFormElement>) {
  e.preventDefault();
  if (!supabase) return;

  const f = new FormData(e.currentTarget);

  const row = {
    organization_id: orgId,
    name: String(f.get('name')).trim(),
    location_type: String(f.get('location_type')),
    description: String(f.get('description')).trim(),
    is_active: true,
  };

  const locationId = editing?.id;
  const isEditing = Boolean(locationId && modal === 'location');

  try {
    const result =
      isEditing && locationId
        ? await supabase
            .from('locations')
            .update(row)
            .eq('id', locationId)
            .eq('organization_id', orgId)
        : await supabase
            .from('locations')
            .insert(row);

    if (result.error) throw result.error;

    await audit(
      isEditing ? 'location.updated' : 'location.created',
      'location',
      { name: row.name }
    );

    await refresh();
    setModal('');
    setEditing(null);
    toast(t('locationSaved'));
  } catch (e: any) {
    toast(friendlyError(e));
  }
}
