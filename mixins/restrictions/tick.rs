// Runs at the head of `Game::native_block_entity_tick` (API 15): one server
// tick of an Attractor or Pusher.
fn observe_tick(
    game: &mut crate::game::Game<'_>,
    pos: [i32; 3],
    entity: &horizon_client::containers::ModBlockEntity,
) {
    crate::game::restrictions_state::on_tick(game, pos, entity);
}
