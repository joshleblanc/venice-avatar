# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_03_154611) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "characters", force: :cascade do |t|
    t.boolean "adult"
    t.datetime "external_created_at"
    t.text "description"
    t.string "name"
    t.string "share_url"
    t.string "slug"
    t.json "stats"
    t.datetime "external_updated_at"
    t.boolean "web_enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "user_created", default: false
    t.text "character_instructions"
    t.integer "user_id"
    t.binary "embedding"
    t.boolean "generating", default: false
    t.text "appearance"
    t.index ["slug"], name: "index_characters_on_slug", unique: true
    t.index ["user_created"], name: "index_characters_on_user_created"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "character_id", null: false
    t.string "title"
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "scene_generating"
    t.boolean "generating_reply"
    t.json "metadata"
    t.boolean "character_away", default: false, null: false
    t.integer "user_id", null: false
    t.index ["character_away"], name: "index_conversations_on_character_away"
    t.index ["character_id"], name: "index_conversations_on_character_id"
    t.index ["updated_at"], name: "index_conversations_on_updated_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.text "content", null: false
    t.string "role", null: false
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "has_pending_followup"
    t.datetime "followup_scheduled_at"
    t.text "followup_context"
    t.string "followup_reason"
    t.integer "user_id", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "scene_prompt_histories", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.text "prompt", null: false
    t.string "trigger", null: false
    t.integer "character_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_scene_prompt_histories_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_scene_prompt_histories_on_conversation_id"
    t.index ["trigger"], name: "index_scene_prompt_histories_on_trigger"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.string "tenant", limit: 128
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "timezone"
    t.string "preferred_image_model", default: "default"
    t.string "preferred_text_model", default: "default"
    t.string "preferred_image_style", default: "Anime"
    t.string "venice_key"
    t.boolean "venice_key_valid"
    t.boolean "admin", default: false
    t.boolean "safe_mode", default: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "characters", "users"
  add_foreign_key "conversations", "characters"
  add_foreign_key "conversations", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users"
  add_foreign_key "scene_prompt_histories", "conversations"
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
end
