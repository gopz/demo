# frozen_string_literal: true

RSpec.describe AdvancedQueueable do
  subject { job.class_eval { include AdvancedQueueable } }

  let(:job) { Class.new { include Sidekiq::Job } }

  describe ".included" do
    before { subject }

    it "extends the base class to include the class method wrappers" do
      expect(job.singleton_class.included_modules).to include(AdvancedQueueable::Wrappers)
    end
  end

  describe AdvancedQueueable::Wrappers do
    before { subject }

    it "overrides the original method set by Sidekiq" do
      expect(job.method(:perform_async).super_method.owner).to eq(Sidekiq::Job::ClassMethods)
    end

    describe ".perform_async" do
      before { allow(job).to receive(:enqueuing_condition_met).and_call_original }

      context "when the including class implements enqueuing_rules" do
        context "when the enqueuing_rule conditions are met" do
          let(:rules) { -> { [{ precedence: 1, type: :max, limit: 1, condition: -> { 0 } }] } }

          before do
            job.define_singleton_method(:enqueuing_rules, rules)
            job.perform_async
          end

          it "calls the perform_async method provided by sidekiq and forwards all arguments" do
            expect(job).to have_received(:enqueuing_condition_met).once
            # TODO: check if perform_async is called on sidekiq
          end
        end

        context "when the enqueuing_rule conditions are not met" do
          context "when a remediation function is defined" do
            it "calls the remediation block" do
              counter = 0
              rules = lambda do
                [{ precedence: 1,
                   type: :max,
                   limit: 1,
                   condition: -> { 1 },
                   remediation: -> { counter += 1 } }]
              end
              job.define_singleton_method(:enqueuing_rules, rules)
              job.perform_async
              expect(counter).to eq(1)
            end
          end

          # This test has a high chance of being flakey and it also takes a while
          context "when the remediation strategy is passed" do
            describe "defer" do
              it "attempts to schedule the including class until the condition is met" do
                now = Time.zone.now
                rules = lambda do
                  [{ precedence: 1,
                     type: :min,
                     limit: now + 2.seconds,
                     condition: -> { Time.zone.now },
                     remediation: [:defer, 1] }]
                end

                job.define_singleton_method(:enqueuing_rules, rules)
                allow(job).to receive(:defer).and_call_original
                job.perform_async
                expect(job).to have_received(:defer).at_least(2)
              end
            end
          end
        end
      end

      context "when the including class does not implement the enqueuing rules" do
        it "raises an exception indicating that the including class does not implement enqueuing_rules" do
          expect { job.perform_async }.to raise_error(NotImplementedError)
        end
      end
    end

    describe ".sort_on_precedence" do
      let(:rule1) { { precedence: 1, type: :max, limit: 1, condition: -> { 0 } } }
      let(:rule2) { { precedence: 2, type: :max, limit: 1, condition: -> { 0 } } }

      context "when a single rule is passed" do
        it "returns the original rule set" do
          expect(job.sort_on_precedence([rule1])).to eq([rule1])
        end
      end

      context "when multiple rules are passed" do
        let(:rules) { [rule2, rule1] }

        it "sorts the rules with the highest precedence being first" do
          expect(job.sort_on_precedence(rules).first[:precedence]).to eq(1)
        end
      end
    end
  end
end
