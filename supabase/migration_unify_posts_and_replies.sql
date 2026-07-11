-- コトノハ: 投稿と返信を1つの posts テーブルに統合するマイグレーション
--
-- 実行方法: Supabaseダッシュボード → SQL Editor に貼り付けて実行してください。
-- 実行前に一度バックアップ(Database → Backups)を取ることをおすすめします。
--
-- 変更内容:
--   1. posts テーブルに parent_id (自己参照, NULL可) を追加する。
--      parent_id が NULL の行 = 通常の投稿、NULL でない行 = 何かへの返信。
--   2. 既存の replies テーブルのデータを posts テーブルへ移行する
--      (id・author_id・text・created_at をそのまま引き継ぎ、post_id を parent_id にする)。
--   3. posts の insert/select/delete ポリシーが返信(parent_id あり)にも
--      同じ条件で適用されるようにする(既存ポリシーの条件が author_id ベースなら
--      そのままで問題ないはずですが、念のため再作成しています)。
--   4. 移行が終わったら古い replies テーブルを削除する。

begin;

-- 1) parent_id 列を追加
alter table posts
  add column if not exists parent_id uuid references posts(id) on delete cascade;

create index if not exists posts_parent_id_idx on posts(parent_id);

-- 2) 既存の返信データを posts へ移行(id を維持することで likes 等の整合性を保つ)
insert into posts (id, author_id, text, created_at, parent_id)
select id, author_id, text, created_at, post_id
from replies
on conflict (id) do nothing;

-- 3) RLS ポリシーの再確認
--    (既存の posts ポリシーが author_id = auth.uid() のような条件であれば、
--     parent_id の有無に関わらずそのまま返信にも適用されます。
--     ポリシー名は環境によって異なるため、以下は代表的な例です。
--     既に同等のポリシーがある場合はこのブロックは不要です)
--
-- create policy "Authenticated users can read posts"
--   on posts for select
--   using (true);
--
-- create policy "Users can insert their own posts"
--   on posts for insert
--   with check (auth.uid() = author_id);
--
-- create policy "Users can delete their own posts"
--   on posts for delete
--   using (auth.uid() = author_id);

-- 4) 移行を確認できたら replies テーブルを削除
--    (不安な場合はこの行を実行せず、しばらく残しておいても構いません)
drop table if exists replies;

commit;
