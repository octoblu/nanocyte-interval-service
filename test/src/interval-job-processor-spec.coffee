IntervalJobProcessor = require '../../src/interval-job-processor'
IORedis = require 'ioredis'
debug = require('debug')('mocha-test')

describe 'IntervalJobProcessor', ->
  beforeEach ->
    @kue = { Job:{} }
    @queue = watchStuckJobs: sinon.spy()
    @kue.createQueue = sinon.spy => @queue
    @kue.Job.get = sinon.spy()
    @redis = new IORedis
    @meshbluMessage = message: sinon.stub()
    dependencies = {}
    dependencies.kue = @kue
    options = {
      minTimeDiff : 150
      @redis
      @meshbluMessage
    }

    @sut = new IntervalJobProcessor options, dependencies

  describe '->processJob', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.getJobs = sinon.stub().yields null, ['some-node-id']
        @sut.removeJobs = sinon.stub()
        @sut.getJobInfo = sinon.stub().yields null, [ true, 60000, 0 ]
        @sut.createJob = sinon.stub().yields null, id: 'a-new-job-id'
        @sut.createPingJob = sinon.stub().yields null, id: 'a-new-ping-job-id'
        @job = data: {sendTo: 'some-flow-id', nodeId: 'some-node-id'}, id: 'some-job-id'
        @sut.processJob @job, {}, (@error) => done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call getJobs', ->
        expect(@sut.getJobs).to.have.been.calledWith @job

      it 'should call removeJobs', ->
        expect(@sut.removeJobs).to.have.been.calledWith ['some-node-id']

      it 'should call getJobInfo', ->
        expect(@sut.getJobInfo).to.have.been.calledWith @job

      it 'should call createJob', ->
        expect(@sut.createJob).to.have.been.called

      it 'should add a job', (done) ->
        @redis.exists 'interval/job/some-flow-id/some-node-id', (error, record) =>
          expect(JSON.parse record).to.equal 1
          done error

      it 'should add a pingJob', (done) ->
        @redis.exists 'interval/pingJob/some-flow-id/some-node-id', (error, record) =>
          expect(JSON.parse record).to.equal 1
          done error

  describe '->getJobs', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.redis.srem = sinon.spy()
        @sut.redis.smembers = sinon.stub().yields null, ['some-node-id']
        job = data: {sendTo: 'some-flow-id', nodeId: 'some-node-id'}
        @sut.getJobs job, (@error) => done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call redis.srem', ->
        expect(@sut.redis.srem).to.have.been.calledWith "interval/job/some-flow-id/some-node-id"

      it 'should call redis.smembers', ->
        expect(@sut.redis.smembers).to.have.been.calledWith "interval/job/some-flow-id/some-node-id"

    describe 'when called with another job', ->
      beforeEach (done) ->
        @sut.removeJobs = sinon.spy()
        @sut.redis.srem = sinon.spy()
        @sut.redis.smembers = sinon.stub().yields null, ['another-node-id']
        job = data: {sendTo: 'another-flow-id', nodeId: 'another-node-id'}
        @sut.getJobs job, (@error) => done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call redis.srem', ->
        expect(@sut.redis.srem).to.have.been.calledWith "interval/job/another-flow-id/another-node-id"

      it 'should call redis.smembers', ->
        expect(@sut.redis.smembers).to.have.been.calledWith "interval/job/another-flow-id/another-node-id"

  describe '->removeJob', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @kue.Job.get = sinon.stub().yields null, remove: sinon.spy()
        @sut.removeJob 'some-node-id', (@error) => done()

      it 'should call kue.get with the job ids', ->
        expect(@kue.Job.get).to.have.been.calledWith 'some-node-id'

    describe 'when called with another job', ->
      beforeEach (done) ->
        @kue.Job.get = sinon.stub().yields null, remove: sinon.spy()
        @sut.removeJob 'another-node-id', (@error) => done()

      it 'should call kue.get with the job ids', ->
        expect(@kue.Job.get).to.have.been.calledWith 'another-node-id'

  describe '->getJobInfo', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        job = data: {sendTo: 'some-flow-id', nodeId: 'some-node-id'}
        jobInfo = [{id:'active'}, {id: 'intervalTime'}, {id: 'cronString'}]
        @sut.redis.mget = sinon.stub().yields null, jobInfo
        @sut.getJobInfo job, (@error, @jobInfo) => done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call redis.mget to be called with keys', ->
        keys = [
          "interval/active/some-flow-id/some-node-id",
          "interval/time/some-flow-id/some-node-id",
          "interval/cron/some-flow-id/some-node-id"
        ]
        expect(@sut.redis.mget).to.be.calledWith keys

      it 'should yield jobInfo', ->
        jobInfo = [{id:'active'}, {id: 'intervalTime'}, {id: 'cronString'}]
        expect(@jobInfo).to.deep.equal jobInfo

    describe 'when called with another job', ->
      beforeEach (done) ->
        job = data: {sendTo: 'another-flow-id', nodeId: 'another-node-id'}
        jobInfo = [{id:'active'}, {id: 'intervalTime'}, {id: 'cronString'}]
        @sut.redis.mget = sinon.stub().yields null, jobInfo
        @sut.getJobInfo job, (@error, @jobInfo) => done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call redis.mget to be called with keys', ->
        keys = [
          "interval/active/another-flow-id/another-node-id",
          "interval/time/another-flow-id/another-node-id",
          "interval/cron/another-flow-id/another-node-id"
        ]
        expect(@sut.redis.mget).to.be.calledWith keys

      it 'should yield jobInfo', ->
        jobInfo = [{id:'active'}, {id: 'intervalTime'}, {id: 'cronString'}]
        expect(@jobInfo).to.deep.equal jobInfo

  describe '->calculateNextCronInterval', ->
    describe 'using a real date with milliseconds set to 0', ->
      now = new Date
      now.setMilliseconds(0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of at most 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- now.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of at most 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of at most 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- now.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of at most 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(900000)

    describe 'using a real date with milliseconds set to 0', ->
      now = new Date
      now.setMilliseconds(0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of at most 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- now.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of at most 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of at most 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- now.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of at most 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(900000)

    describe 'using a fake date', ->
      fakeDate = new Date(2015, 0, 1, 15, 0, 0, 0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- fakeDate.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(result).to.equals(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(900000)

      describe 'when called with an invalid cron string', ->
        it 'should throw an error', ->
          hasError = false
          try
            @sut.calculateNextCronInterval "*/1000E * * * * *", fakeDate
          catch error
            hasError = true
          expect(hasError).to.equals true

    describe 'using a fake date with milliseconds set close to an interval', ->
      fakeDate = new Date(2015, 0, 1, 12, 59, 59, 850)

      describe 'when called with seconds option', ->
        it 'should result in a next time of 1150 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- fakeDate.getSeconds()
          if nextSecond < 0
            nextSecond = nextSecond + 60
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute < 0
            nextMinute = nextMinute + 60
          nextHour = nextDate.getHours()- fakeDate.getHours()
          expect(nextSecond).to.equal 2
          expect(nextMinute).to.equal 1
          expect(nextHour).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(1150)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of 15150 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(15150)

      describe 'when called with minutes option', ->
        it 'should result in a next time of 60150 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute < 0
            nextMinute = nextMinute + 60
          nextHour = nextDate.getHours()- fakeDate.getHours()
          expect(nextMinute).to.equal 2
          expect(nextHour).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(result).to.equals(60150)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of 900150 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(900150)