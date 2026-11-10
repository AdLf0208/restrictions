// `getStateForPlacement`: a Restrictions block keeps the placer's horizontal
// facing, as McJtyLib's BaseBlock does with OrientationTools.getFacingFromEntity.
fn observe_state_for_placement(
    level: &crate::game::GameLevel<'_>,
    state: BlockStateId,
    context: &PlacementContext,
    answer: &mut Option<Option<BlockStateId>>,
) {
    crate::game::restrictions_state::on_state_for_placement(level, state, context, answer);
}
