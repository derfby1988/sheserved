async function resolveEmergencyCategoryNames(supabase, videos) {
  const categoryIds = [
    ...new Set(
      videos
        .map((video) => video.category_id?.toString())
        .filter((id) => id),
    ),
  ];
  if (!supabase || categoryIds.length === 0) return videos;

  const { data, error } = await supabase
    .from('donation_categories')
    .select('id, name')
    .in('id', categoryIds);
  if (error) throw error;

  const categoryNames = new Map(
    (data ?? [])
      .map((category) => [category.id?.toString(), category.name?.toString().trim()])
      .filter(([id, name]) => id && name),
  );

  return videos.map((video) => {
    const categoryName = categoryNames.get(video.category_id?.toString());
    return categoryName ? { ...video, category_name: categoryName } : video;
  });
}

module.exports = { resolveEmergencyCategoryNames };
