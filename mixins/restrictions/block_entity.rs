// Runs at the head of `Game::native_block_entity` (API 15): the two mover
// blocks declare a block entity.
fn observe_block_entity(block: &str, entity: &mut Option<(String, horizon_world::nbt::Compound)>) {
    crate::game::restrictions_state::on_block_entity(block, entity);
}
