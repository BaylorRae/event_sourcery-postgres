RSpec.describe EventSourcery::Postgres::Tracker do
  subject(:postgres_tracker) { described_class.new(db_connection, table_name: table_name) }
  let(:table_name) { :tracker }
  let(:processor_name) { 'blah' }
  let(:table) { db_connection[table_name] }
  let(:track_entry) { table.where(name: processor_name).first }

  after do
    release_advisory_locks
  end

  def last_processed_event_id
    postgres_tracker.last_processed_event_id(processor_name)
  end

  def setup_table
    db_connection.execute "drop table if exists #{table_name}"
    postgres_tracker.setup(processor_name)
  end

  describe '#setup' do
    before do
      db_connection.execute "drop table if exists #{table_name}"
    end

    context 'auto create projector tracker enabled' do
      it 'creates the table' do
        postgres_tracker.setup(processor_name)
        expect(db_connection.table_exists?(table_name)).to be_truthy
      end

      it "creates an entry for the projector if it doesn't exist" do
        postgres_tracker.setup(processor_name)
        expect(last_processed_event_id).to eq 0
      end
    end

    context 'when table_name is a string' do
      let(:table_name) { 'tracker' }

      it 'does not raise an error' do
        expect { postgres_tracker.setup(processor_name) }.not_to raise_error
      end

      it 'creates the table' do
        postgres_tracker.setup(processor_name)
        expect(db_connection.table_exists?(table_name)).to be_truthy
      end
    end

    context 'auto create projector tracker disabled' do
      before do
        allow(EventSourcery::Postgres.config).to receive(:auto_create_projector_tracker).and_return(false)
      end

      it 'raises error' do
        expect { postgres_tracker.setup(processor_name) }.to raise_error EventSourcery::UnableToLockProcessorError
      end
    end
  end

  describe '#processed_event' do
    before { setup_table }

    it 'updates the tracker entry to the given ID' do
      postgres_tracker.processed_event(processor_name, 1)
      expect(last_processed_event_id).to eq 1
    end
  end

  describe '#processing_event' do
    before { setup_table }

    context 'when the block succeeds' do
      it 'marks the event as processed' do
        postgres_tracker.processing_event(processor_name, 1) do
        end
        expect(last_processed_event_id).to eq 1
      end
    end

    context 'when the block raises' do
      it "doesn't mark the event as processed and raises an error" do
        expect(last_processed_event_id).to eq 0
        expect do
          postgres_tracker.processing_event(processor_name, 1) do
            raise 'boo'
          end
        end.to raise_error(RuntimeError)
        expect(last_processed_event_id).to eq 0
      end
    end

    context 'unable to lock tracker row' do
      let(:another_database_connection) { new_db_connection }

      it 'raises an error' do
        expect do
          tracker = described_class.new(another_database_connection, table_name: table_name)
          tracker.setup(processor_name)
        end.to raise_error(EventSourcery::UnableToLockProcessorError)
      end

      context 'with obtain_processor_lock: false' do
        it "doesn't raises an error" do
          expect do
            tracker = described_class.new(another_database_connection, table_name: table_name, obtain_processor_lock: false)
            tracker.setup(processor_name)
          end.to_not raise_error
        end
      end

      after { release_advisory_locks(another_database_connection) }
    end
  end

  describe '#last_processed_event_id' do
    before { setup_table }

    it 'starts at 0' do
      expect(last_processed_event_id).to eq 0
    end

    it 'updates as events are processed' do
      postgres_tracker.processed_event(processor_name, 1)
      expect(last_processed_event_id).to eq 1
    end
  end

  describe '#reset_last_processed_event_id' do
    before { setup_table }

    it 'resets the last processed event back to 0' do
      postgres_tracker.processed_event(processor_name, 1)
      postgres_tracker.reset_last_processed_event_id(processor_name)
      expect(last_processed_event_id).to eq 0
    end
  end

  describe '#tracked_processors' do
    before do
      db_connection.execute "drop table if exists #{table_name}"
      postgres_tracker.setup
    end

    context 'with two tracked processors' do
      before do
        postgres_tracker.setup(:one)
        postgres_tracker.setup(:two)
      end

      it 'returns an array of tracked processors' do
        expect(postgres_tracker.tracked_processors).to eq ['one', 'two']
      end
    end

    context 'with no tracked processors' do
      it 'returns an empty array' do
        expect(postgres_tracker.tracked_processors).to eq []
      end
    end
  end
end
