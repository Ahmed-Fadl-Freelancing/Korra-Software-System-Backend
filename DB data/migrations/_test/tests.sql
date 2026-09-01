\set ON_ERROR_STOP on
-- helper: assert that a statement fails, and that the message mentions what we expect
CREATE OR REPLACE FUNCTION must_fail(p_sql text, p_expect text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    IF position(lower(p_expect) in lower(SQLERRM)) = 0 THEN
      RAISE EXCEPTION 'FAIL %: failed but for the wrong reason: %', p_label, SQLERRM;
    END IF;
    RAISE NOTICE 'pass  %', p_label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement SUCCEEDED but should have been rejected', p_label;
END $$;

CREATE OR REPLACE FUNCTION assert_eq(p_got anyelement, p_want anyelement, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_got IS DISTINCT FROM p_want THEN
    RAISE EXCEPTION 'FAIL %: got % want %', p_label, p_got, p_want;
  END IF;
  RAISE NOTICE 'pass  % (%)', p_label, p_got;
END $$;

-- ============================ seed ============================
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111','sales@korra.test'),
  ('22222222-2222-2222-2222-222222222222','tech@korra.test'),
  ('33333333-3333-3333-3333-333333333333','tech2@korra.test');
INSERT INTO public.departments (id,name) VALUES ('dddddddd-0000-0000-0000-000000000001','tech_office');
INSERT INTO public.user_profiles (user_id, employee_code, full_name, department_id) VALUES
  ('11111111-1111-1111-1111-111111111111','E1','Sales Eng', NULL),
  ('22222222-2222-2222-2222-222222222222','E2','Tech Eng','dddddddd-0000-0000-0000-000000000001'),
  ('33333333-3333-3333-3333-333333333333','E3','Tech Eng 2','dddddddd-0000-0000-0000-000000000001');
INSERT INTO public.roles (id, code, name) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001','tech_engineer','Technical Engineer'),
  ('aaaaaaaa-0000-0000-0000-000000000002','tech_office','Technical Office');
-- user 2 deliberately holds BOTH roles, to prove the fan-out dedupes
INSERT INTO public.user_roles (user_id, role_id) VALUES
  ('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-000000000002'),
  ('33333333-3333-3333-3333-333333333333','aaaaaaaa-0000-0000-0000-000000000001');
INSERT INTO public.products (id, family, chiller_condenser, chiller_compressor, model_code, name) VALUES
  ('cccccccc-0000-0000-0000-000000000001','Chiller','AirCooled','Screw','CH-100','Chiller 100TR');
INSERT INTO public.products (id, family, model_code, name) VALUES
  ('cccccccc-0000-0000-0000-000000000002','Pump','PU-50','Pump 50');
INSERT INTO public.competitors (id, name) VALUES ('bbbbbbbb-0000-0000-0000-000000000001','Carrier');
INSERT INTO public.projects (id, name, sales_eng_id, tech_off_eng_id, application, scope, tender_stage, bid_due_date)
VALUES ('eeeeeeee-0000-0000-0000-000000000001','Tower A','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','Commercial','Supply','inHand', current_date + 2);

-- ============================ A. the headline scenario ============================
-- 3 chillers + 4 pumps on one project
INSERT INTO public.project_items (id, project_id, product_family, product_id, quantity, unit_price, competitor_id, competitor_price, label, position)
VALUES ('ffffffff-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001','Chiller','cccccccc-0000-0000-0000-000000000001',3,50000,'bbbbbbbb-0000-0000-0000-000000000001',47000,'Roof',0),
       ('ffffffff-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000001','Pump','cccccccc-0000-0000-0000-000000000002',4,8000,'bbbbbbbb-0000-0000-0000-000000000001',8500,'Basement',1);

SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000001'),
                 'tenderingPhase', 'EC2/EC3 lines added, all pending -> no roll-up');

-- Decide the pump won and the chiller lost, WITHOUT setting app.user_id first.
-- This is edge case 7: the roll-up UPDATEs projects, which fires the audit trigger that demands the
-- GUC. If the roll-up did not set it itself, this hand-edit would fail naming a table not touched.
UPDATE public.project_items SET line_status='won', win_reason='price', decided_at=now(),
       decided_by_user_id='11111111-1111-1111-1111-111111111111'
 WHERE id='ffffffff-0000-0000-0000-000000000002';
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000001'),
                 'tenderingPhase', 'EC2 one line still pending -> still no roll-up');

UPDATE public.project_items SET line_status='lost', loss_reason='technical', decided_at=now(),
       decided_by_user_id='11111111-1111-1111-1111-111111111111'
 WHERE id='ffffffff-0000-0000-0000-000000000001';
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000001'),
                 'partiallyWon', 'EC1 won pumps + lost chillers -> partiallyWon');
SELECT assert_eq((SELECT count(*)::int FROM public.project_status_history
                  WHERE project_id='eeeeeeee-0000-0000-0000-000000000001'), 1,
                 'EC7 audit row written, app.user_id supplied by the roll-up itself');

-- awarded_quantity defaulted on win
SELECT assert_eq((SELECT awarded_quantity FROM public.project_items WHERE id='ffffffff-0000-0000-0000-000000000002'),
                 4, 'D1 awarded_quantity defaults to quantity on win');
-- client awards 2 of the 4 pumps: sales engineer edits it down, no loss recorded
UPDATE public.project_items SET awarded_quantity=2 WHERE id='ffffffff-0000-0000-0000-000000000002';
SELECT assert_eq((SELECT quantity_shortfall::int FROM public.v_project_item_outcomes WHERE item_id='ffffffff-0000-0000-0000-000000000002'),
                 2, 'D1 shortfall visible as quantity - awarded_quantity');
SELECT assert_eq((SELECT won_value FROM public.v_project_item_outcomes WHERE item_id='ffffffff-0000-0000-0000-000000000002'),
                 16000::numeric, 'rule 5 revenue uses awarded_quantity, not quantity');

-- EC31: flip won -> lost, awarded_quantity must clear itself
UPDATE public.project_items SET line_status='lost', loss_reason='price', win_reason=NULL
 WHERE id='ffffffff-0000-0000-0000-000000000002';
SELECT assert_eq((SELECT awarded_quantity FROM public.project_items WHERE id='ffffffff-0000-0000-0000-000000000002'),
                 NULL::int, 'EC31 awarded_quantity cleared when a won line flips to lost');
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000001'),
                 'lost', 'EC5 re-deciding recomputes the roll-up: now all lost');
-- put it back for the later view tests
UPDATE public.project_items SET line_status='won', win_reason='price', loss_reason=NULL, awarded_quantity=NULL
 WHERE id='ffffffff-0000-0000-0000-000000000002';
UPDATE public.project_items SET awarded_quantity=2 WHERE id='ffffffff-0000-0000-0000-000000000002';

-- ============================ B. the CHECK constraints ============================
SELECT must_fail($$UPDATE public.project_items SET line_status='won', win_reason=NULL WHERE id='ffffffff-0000-0000-0000-000000000001'$$,
                 'won_reason_chk', 'EC8 won with no win_reason');
SELECT must_fail($$UPDATE public.project_items SET line_status='lost', loss_reason='price', win_reason='price' WHERE id='ffffffff-0000-0000-0000-000000000001'$$,
                 'lost_reason_chk', 'EC9 lost carrying a leftover win_reason');
SELECT must_fail($$UPDATE public.project_items SET line_status='pending', win_reason='price', decided_at=NULL WHERE id='ffffffff-0000-0000-0000-000000000001'$$,
                 'open_reason_chk', 'EC10 pending line carrying a reason');
SELECT must_fail($$UPDATE public.project_items SET line_status='lost', loss_reason='price', win_reason=NULL, decided_at=NULL WHERE id='ffffffff-0000-0000-0000-000000000001'$$,
                 'decided_at_chk', 'EC11 decided line with no decided_at');
SELECT must_fail($$INSERT INTO public.project_items (project_id, product_family, quantity) VALUES ('eeeeeeee-0000-0000-0000-000000000001','Pump',0)$$,
                 'quantity_check', 'EC16 quantity = 0');
SELECT must_fail($$UPDATE public.project_items SET awarded_quantity=99 WHERE id='ffffffff-0000-0000-0000-000000000002'$$,
                 'awarded_qty_chk', 'EC30 awarded_quantity > quantity');
SELECT must_fail($$UPDATE public.project_items SET awarded_quantity=1 WHERE id='ffffffff-0000-0000-0000-000000000001'$$,
                 'may only be set on a won line', 'EC29 awarded_quantity on a line that is not won');

-- ============================ C. products & lines ============================
SELECT must_fail($$INSERT INTO public.project_items (project_id, product_family, product_id, quantity)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','Pump','cccccccc-0000-0000-0000-000000000001',1)$$,
                 'product_family_fk', 'EC13 Pump line pointed at a Chiller product');
-- EC12: family-only line, product_id NULL -> allowed (this is the intake default)
INSERT INTO public.project_items (id, project_id, product_family, quantity, position)
VALUES ('ffffffff-0000-0000-0000-000000000003','eeeeeeee-0000-0000-0000-000000000001','Generator',1,2);
SELECT assert_eq((SELECT count(*)::int FROM public.project_items WHERE id='ffffffff-0000-0000-0000-000000000003'),
                 1, 'EC12 family-only line with NULL product_id is allowed');
-- EC15: same product twice on one project (Building A / Building B)
INSERT INTO public.project_items (id, project_id, product_family, product_id, quantity, label, position)
VALUES ('ffffffff-0000-0000-0000-000000000004','eeeeeeee-0000-0000-0000-000000000001','Chiller','cccccccc-0000-0000-0000-000000000001',2,'Building B',3);
SELECT assert_eq((SELECT count(*)::int FROM public.project_items
                  WHERE project_id='eeeeeeee-0000-0000-0000-000000000001' AND product_id='cccccccc-0000-0000-0000-000000000001'),
                 2, 'EC15 the same model appears twice on one project');
-- EC14: the live Chiller gate still bites
SELECT must_fail($$INSERT INTO public.products (family, model_code) VALUES ('Chiller','CH-BAD')$$,
                 'chiller_gate', 'EC14 Chiller product without condenser/compressor');

-- ============================ D. zero lines ============================
INSERT INTO public.projects (id, name, sales_eng_id, application, scope)
VALUES ('eeeeeeee-0000-0000-0000-000000000002','Empty Project','11111111-1111-1111-1111-111111111111','Industrial','Supply');
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000002'),
                 'tenderingPhase', 'EC3 project with zero lines is untouched, no crash');
SELECT assert_eq((SELECT total_lines::int FROM public.v_project_rollup WHERE project_id='eeeeeeee-0000-0000-0000-000000000002'),
                 0, 'EC27 zero-line project reports 0 lines, not a phantom');

-- ============================ E. notes & review ============================
SELECT must_fail($$INSERT INTO public.project_notes (project_id, body, position, created_by_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','   ',1,'11111111-1111-1111-1111-111111111111')$$,
                 'body_check', 'EC17 whitespace-only note');
INSERT INTO public.project_notes (id, project_id, body, position, created_by_user_id) VALUES
  ('aaaa0000-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001','Client dropped the 3rd chiller',1,'11111111-1111-1111-1111-111111111111'),
  ('aaaa0000-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000001','And wants 2 more pumps',2,'11111111-1111-1111-1111-111111111111');
-- EC22: fractional reorder writes one row
UPDATE public.project_notes SET position = (1 + 2)::numeric / 2 WHERE id='aaaa0000-0000-0000-0000-000000000002';
SELECT assert_eq((SELECT position FROM public.project_notes WHERE id='aaaa0000-0000-0000-0000-000000000002'),
                 1.5::numeric, 'EC22 fractional position, no renumbering');

-- EC18: a review request without a note is structurally impossible
SELECT must_fail($$INSERT INTO public.project_review_requests (project_id, requested_by_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111')$$,
                 'note_id', 'EC18 review request with no note (NOT NULL)');
-- EC20: requesting review from yourself
SELECT must_fail($$INSERT INTO public.project_review_requests (project_id, note_id, requested_by_user_id, requested_to_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaa0000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111')$$,
                 'not_self_chk', 'EC20 requesting review from yourself');

-- the real thing: unassigned request fans out to the technical office
INSERT INTO public.project_review_requests (id, project_id, note_id, requested_by_user_id, message)
VALUES ('bbbb0000-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001','aaaa0000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','please check');
SELECT assert_eq((SELECT count(*)::int FROM public.notifications WHERE entity_id='bbbb0000-0000-0000-0000-000000000001'),
                 2, 'EC24 fan-out reaches both tech engineers');
SELECT assert_eq((SELECT count(*)::int FROM public.notifications
                  WHERE entity_id='bbbb0000-0000-0000-0000-000000000001' AND user_id='22222222-2222-2222-2222-222222222222'),
                 1, 'EC24 the user holding TWO tech roles gets exactly one notification');
SELECT assert_eq((SELECT count(*)::int FROM public.notifications
                  WHERE entity_id='bbbb0000-0000-0000-0000-000000000001' AND user_id='11111111-1111-1111-1111-111111111111'),
                 0, 'the requester does not notify themselves');
SELECT assert_eq((SELECT title FROM public.notifications WHERE entity_id='bbbb0000-0000-0000-0000-000000000001' LIMIT 1),
                 'note added on Tower A — please check it out', 'notification wording');

-- EC19: a second open request on the same note
SELECT must_fail($$INSERT INTO public.project_review_requests (project_id, note_id, requested_by_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaa0000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111')$$,
                 'one_open_per_note', 'EC19 second pending request on the same note');
-- ...but once resolved, a new one is allowed
UPDATE public.project_review_requests SET status='resolved', resolved_at=now() WHERE id='bbbb0000-0000-0000-0000-000000000001';
INSERT INTO public.project_review_requests (project_id, note_id, requested_by_user_id)
VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaa0000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111');
SELECT assert_eq((SELECT count(*)::int FROM public.project_review_requests WHERE note_id='aaaa0000-0000-0000-0000-000000000001'),
                 2, 'a resolved request does not block the next one');

-- EC21: soft-deleted note -> its request survives, but no NEW request can be raised on it
UPDATE public.project_notes SET deleted_at=now(), deleted_by_user_id='11111111-1111-1111-1111-111111111111'
 WHERE id='aaaa0000-0000-0000-0000-000000000002';
SELECT must_fail($$INSERT INTO public.project_review_requests (project_id, note_id, requested_by_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaa0000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111')$$,
                 'deleted note', 'EC21 review request on a soft-deleted note');
-- cross-project note
SELECT must_fail($$INSERT INTO public.project_review_requests (project_id, note_id, requested_by_user_id)
                   VALUES ('eeeeeeee-0000-0000-0000-000000000002','aaaa0000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111')$$,
                 'belongs to project', 'note from another project');

-- ============================ F. tender stage ============================
INSERT INTO public.projects (id, name, sales_eng_id, application, scope, tender_stage)
VALUES ('eeeeeeee-0000-0000-0000-000000000003','Tender Job','11111111-1111-1111-1111-111111111111','Commercial','Supply','inTender');
INSERT INTO public.project_items (id, project_id, product_family, quantity, unit_price, position) VALUES
  ('ffff1111-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000003','Chiller',2,60000,0),
  ('ffff1111-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003','Pump',5,9000,1);
-- one line genuinely won before the contractor's own bid collapsed
UPDATE public.project_items SET line_status='won', win_reason='technical', decided_at=now(),
       decided_by_user_id='11111111-1111-1111-1111-111111111111' WHERE id='ffff1111-0000-0000-0000-000000000002';
SELECT public.project_contractor_lost_tender('eeeeeeee-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111');
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000003'),
                 'withDifferentContractor', 'EC34 contractor lost tender -> withDifferentContractor');
SELECT assert_eq((SELECT line_status::text FROM public.project_items WHERE id='ffff1111-0000-0000-0000-000000000001'),
                 'lost', 'open line killed');
SELECT assert_eq((SELECT loss_reason::text FROM public.project_items WHERE id='ffff1111-0000-0000-0000-000000000001'),
                 'contractor_lost_tender', 'killed with the honest reason, not "price"');
SELECT assert_eq((SELECT line_status::text FROM public.project_items WHERE id='ffff1111-0000-0000-0000-000000000002'),
                 'won', 'EC34 the already-won line keeps its outcome');
-- EC35: deciding another line now must NOT relabel the project 'lost'
UPDATE public.project_items SET line_status='lost', loss_reason='price', win_reason=NULL
 WHERE id='ffff1111-0000-0000-0000-000000000002';
SELECT assert_eq((SELECT status::text FROM public.projects WHERE id='eeeeeeee-0000-0000-0000-000000000003'),
                 'withDifferentContractor', 'EC35 terminal status is never overwritten by the roll-up');
-- EC36: calling the kill twice is a no-op
SELECT public.project_contractor_lost_tender('eeeeeeee-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111');
SELECT assert_eq((SELECT count(*)::int FROM public.project_status_history WHERE project_id='eeeeeeee-0000-0000-0000-000000000003'),
                 1, 'EC36 second kill writes no second history row');

-- ============================ G. analytics rules ============================
-- rule 3: tender attrition is not a competitive loss
SELECT assert_eq((SELECT tender_attrition_lines::int FROM public.v_win_rate_by_family WHERE product_family='Chiller'),
                 1, 'rule 3 tender attrition counted separately');
-- 2 chiller lines are 'lost' in total: one to a competitor, one because the contractor lost his
-- own tender. The view must split them, not add them.
SELECT assert_eq((SELECT count(*)::int FROM public.project_items
                  WHERE product_family='Chiller' AND line_status='lost'),
                 2, 'two chiller lines are lost in raw data');
SELECT assert_eq((SELECT lost_lines::int FROM public.v_win_rate_by_family WHERE product_family='Chiller'),
                 1, 'rule 3 only ONE of them is a competitive loss');
-- rule 1: cancelled lines vanish from the base view
UPDATE public.project_items SET line_status='cancelled', win_reason=NULL, loss_reason=NULL, decided_at=NULL
 WHERE id='ffffffff-0000-0000-0000-000000000004';
SELECT assert_eq((SELECT count(*)::int FROM public.v_project_item_outcomes WHERE item_id='ffffffff-0000-0000-0000-000000000004'),
                 0, 'EC4/rule 1 cancelled line excluded from the outcomes view');
-- price delta
SELECT assert_eq((SELECT price_delta_pct FROM public.v_project_item_outcomes WHERE item_id='ffffffff-0000-0000-0000-000000000001'),
                 6.38::numeric, 'price_delta_pct: 50000 vs 47000 = +6.38% more expensive');
-- EC26: win rate denominator
SELECT assert_eq((SELECT win_rate_pct FROM public.v_win_rate_by_family WHERE product_family='Pump'),
                 50.0::numeric, 'EC26 Pump win rate = 1 won / (1 won + 1 lost)');
-- work queue: in-hand + due in 2 days outranks the in-tender job
SELECT assert_eq((SELECT count(*)::int FROM public.v_work_queue WHERE project_id='eeeeeeee-0000-0000-0000-000000000003'),
                 0, 'terminal project drops out of the work queue');
SELECT assert_eq((SELECT priority_score::int FROM public.v_work_queue WHERE project_id='eeeeeeee-0000-0000-0000-000000000001'),
                 800, 'in-hand (500) + due in 2 days (300) = 800');
-- the empty project has no deadline and no lines: it is in the queue purely because it needs intake
SELECT assert_eq((SELECT priority_score::int FROM public.v_work_queue WHERE project_id='eeeeeeee-0000-0000-0000-000000000002'),
                 75, 'a project with zero lines is in the queue, needing intake');
-- EC38: tender group counted once
UPDATE public.projects SET tender_group_id=NULL WHERE id IS NOT NULL;
INSERT INTO public.tender_groups (id, name) VALUES ('99990000-0000-0000-0000-000000000001','Tower A tender');
UPDATE public.projects SET tender_group_id='99990000-0000-0000-0000-000000000001'
 WHERE id IN ('eeeeeeee-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000003');
SELECT assert_eq((SELECT count(*)::int FROM public.v_tender_group_outcomes WHERE group_key='99990000-0000-0000-0000-000000000001'),
                 1, 'EC38 two projects, one end job, one row');
SELECT assert_eq((SELECT korra_won_any FROM public.v_tender_group_outcomes WHERE group_key='99990000-0000-0000-0000-000000000001'),
                 true, 'EC38 the group is a win because one route through it won');

SELECT 'ALL TESTS PASSED' AS result;
